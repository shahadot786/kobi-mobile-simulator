//
//  AutoReloadMonitor.swift
//  Kobi
//
//  Phase 12 — Dev-server auto-sync: "Watch mode" polls the loaded document for changes and
//  triggers a reload — the generic alternative to wiring a specific dev server's HMR/WebSocket
//  protocol, which varies per bundler (Vite, webpack-dev-server, Next.js, etc.) and isn't
//  something a single implementation could target generically.
//
//  Limitation: this only detects changes to the polled document's own bytes. A dev server that
//  serves an unchanged HTML shell while only its bundled JS/CSS changes (common with client-side
//  routing) won't be caught — the same limitation the roadmap's "Last-Modified/ETag" approach
//  has, since here comparison is by raw response body rather than headers, done because many
//  local dev servers don't reliably set caching headers in development mode.
//

import Foundation

final class AutoReloadMonitor {
    private var timer: Timer?
    private var lastBody: Data?
    private let session = URLSession(configuration: .ephemeral)
    private var pollTask: Task<Void, Never>?

    deinit {
        timer?.invalidate()
        pollTask?.cancel()
    }

    func start(url: URL, interval: TimeInterval = 1.5, onChange: @escaping () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll(url: url, onChange: onChange)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        pollTask = nil
        lastBody = nil
    }

    private func poll(url: URL, onChange: @escaping () -> Void) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 2
            guard let (data, _) = try? await session.data(for: request) else { return }
            guard !Task.isCancelled else { return }
            if let lastBody, lastBody != data {
                await MainActor.run { onChange() }
            }
            lastBody = data
        }
    }
}
