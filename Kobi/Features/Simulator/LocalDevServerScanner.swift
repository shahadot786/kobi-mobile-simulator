//
//  LocalDevServerScanner.swift
//  Kobi
//
//  Phase 12 — Dev-server auto-sync: scans common local dev-server ports so a running server can
//  be picked as a one-click load target instead of typing the URL by hand.
//

import Foundation

enum LocalDevServerScanner {
    static let commonPorts = [3000, 5173, 5174, 8080, 4200, 8000]

    static func scan() async -> [Int] {
        await withTaskGroup(of: Int?.self) { group in
            for port in commonPorts {
                group.addTask {
                    await isPortOpen(port) ? port : nil
                }
            }
            var openPorts: [Int] = []
            for await result in group {
                if let port = result {
                    openPorts.append(port)
                }
            }
            return openPorts.sorted()
        }
    }

    private static func isPortOpen(_ port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: .ephemeral)
        return await (try? session.data(for: request)) != nil
    }
}
