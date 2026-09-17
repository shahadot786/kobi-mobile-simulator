//
//  ThrottleProxyServer.swift
//  Kobi
//
//  Phase 5 — network throttling. `WKWebView`'s networking runs in a separate WebContent
//  process that never consults the host app's `URLProtocol`/`URLSession` configuration, and
//  WebKit refuses to let apps register a scheme handler for `http`/`https`. There is no public
//  per-`WKWebView` proxy hook either (checked current WebKit/Network docs). The only thing that
//  actually works without a system-wide OS proxy prompt or a Network Extension entitlement: run
//  our own local reverse proxy and load the page through it. This throttles the loaded origin's
//  own traffic (the actual use case — testing your own dev server) but not unrelated
//  third-party/CDN requests the page happens to also make.
//

import Foundation
import Network

enum NetworkThrottlePreset: String, CaseIterable, Identifiable {
    case none
    case fast4G
    case slow3G
    case offline

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .none: String(localized: "networkThrottle.none")
        case .fast4G: String(localized: "networkThrottle.fast4G")
        case .slow3G: String(localized: "networkThrottle.slow3G")
        case .offline: String(localized: "networkThrottle.offline")
        }
    }

    var isOffline: Bool {
        self == .offline
    }

    var latencyMilliseconds: UInt64 {
        switch self {
        case .none: 0
        case .fast4G: 100
        case .slow3G: 400
        case .offline: 0
        }
    }

    /// The proxy paces response bytes to approximate this rate, chunking output so large
    /// assets visibly take longer. Not a byte-accurate network simulator — just enough to make
    /// "slow network" perceptible while testing a dev server.
    var downloadBytesPerSecond: Int? {
        switch self {
        case .none, .offline: nil
        case .fast4G: 187_500 // ~1.5 Mbps
        case .slow3G: 50000 // ~400 Kbps
        }
    }
}

enum ThrottleProxyError: LocalizedError {
    case startFailed

    var errorDescription: String? {
        switch self {
        case .startFailed: String(localized: "simulator.error.throttleStartFailed")
        }
    }
}

/// A minimal local HTTP/1.1 reverse proxy — bound to loopback only — that forwards requests to
/// a single upstream host/port and replays responses with artificial latency/bandwidth pacing.
/// Scoped to the dev-server use case: no HTTPS termination, no WebSocket upgrade, no request
/// bodies beyond what a simple page-load GET needs.
final class ThrottleProxyServer {
    private var listener: NWListener?
    private var upstreamHost = ""
    private var upstreamPort: UInt16 = 80
    private var preset: NetworkThrottlePreset = .none
    private let session = URLSession(configuration: .ephemeral)

    deinit {
        listener?.cancel()
    }

    func start(upstreamHost: String, upstreamPort: UInt16, preset: NetworkThrottlePreset) async throws -> UInt16 {
        stop()
        self.upstreamHost = upstreamHost
        self.upstreamPort = upstreamPort
        self.preset = preset

        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let newListener = try NWListener(using: parameters, on: .any)
        listener = newListener

        return try await withCheckedThrowingContinuation { continuation in
            let resumeGuard = OneShotFlag()
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.markFirstFire() else { return }
                    if let boundPort = newListener.port {
                        continuation.resume(returning: boundPort.rawValue)
                    } else {
                        continuation.resume(throwing: ThrottleProxyError.startFailed)
                    }
                case .failed, .cancelled:
                    guard resumeGuard.markFirstFire() else { return }
                    continuation.resume(throwing: ThrottleProxyError.startFailed)
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { @MainActor in
                    self.accept(connection)
                }
            }
            newListener.start(queue: .main)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer[..<headerEnd.lowerBound]
                guard let headerText = String(data: headerData, encoding: .utf8),
                      let request = ParsedHTTPRequest(headerText: headerText)
                else {
                    connection.cancel()
                    return
                }
                forward(request: request, on: connection)
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }
            receiveRequest(on: connection, buffer: buffer)
        }
    }

    private func forward(request: ParsedHTTPRequest, on connection: NWConnection) {
        guard !preset.isOffline else {
            connection.cancel()
            return
        }

        guard var components = URLComponents(string: request.path) else {
            connection.cancel()
            return
        }
        components.scheme = "http"
        components.host = upstreamHost
        components.port = Int(upstreamPort)
        guard let url = components.url else {
            connection.cancel()
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers where key.lowercased() != "host" {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.setValue("\(upstreamHost):\(upstreamPort)", forHTTPHeaderField: "Host")

        let latencyMilliseconds = preset.latencyMilliseconds
        let bytesPerSecond = preset.downloadBytesPerSecond

        Task {
            if latencyMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: latencyMilliseconds * 1_000_000)
            }
            do {
                let (data, response) = try await session.data(for: urlRequest)
                await self.writeResponse(
                    data: data,
                    response: response as? HTTPURLResponse,
                    bytesPerSecond: bytesPerSecond,
                    on: connection
                )
            } catch {
                connection.cancel()
            }
        }
    }

    private func writeResponse(
        data: Data,
        response: HTTPURLResponse?,
        bytesPerSecond: Int?,
        on connection: NWConnection
    ) async {
        let statusCode = response?.statusCode ?? 200
        var headerLines = ["HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))"]
        var sawContentLength = false
        for (key, value) in response?.allHeaderFields ?? [:] {
            guard let keyString = key as? String, let valueString = value as? String else { continue }
            let lowercasedKey = keyString.lowercased()
            // We already decoded the body via URLSession and aren't re-compressing/re-chunking
            // it, so these transport-level headers from the upstream response no longer apply.
            if lowercasedKey == "content-encoding" || lowercasedKey == "transfer-encoding" {
                continue
            }
            if lowercasedKey == "content-length" {
                sawContentLength = true
            }
            headerLines.append("\(keyString): \(valueString)")
        }
        if !sawContentLength {
            headerLines.append("Content-Length: \(data.count)")
        }
        headerLines.append("Connection: close")
        let headerText = headerLines.joined(separator: "\r\n") + "\r\n\r\n"

        await send(Data(headerText.utf8), on: connection)

        guard let bytesPerSecond, bytesPerSecond > 0 else {
            await send(data, on: connection)
            connection.cancel()
            return
        }

        let chunkSize = max(bytesPerSecond / 10, 512) // ~100ms worth of data per chunk
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            await send(data.subdata(in: offset ..< end), on: connection)
            offset = end
            if offset < data.count {
                let delaySeconds = Double(chunkSize) / Double(bytesPerSecond)
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
        connection.cancel()
    }

    private func send(_ data: Data, on connection: NWConnection) async {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}

/// A lock-based one-shot guard for `NWListener.stateUpdateHandler`, which Network.framework
/// delivers as a plain (non-actor-isolated) closure — a `Bool` captured directly by that
/// closure isn't provably safe to mutate under Swift's concurrency checker, even though it's
/// only ever invoked serially on the `.main` queue we requested.
private final nonisolated class OneShotFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFired = false

    func markFirstFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasFired {
            return false
        }
        hasFired = true
        return true
    }
}

private struct ParsedHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]

    init?(headerText: String) {
        let lines = headerText.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        path = String(parts[1])

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex ..< colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            parsedHeaders[key] = value
        }
        headers = parsedHeaders
    }
}
