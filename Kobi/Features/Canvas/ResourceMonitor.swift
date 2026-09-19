//
//  ResourceMonitor.swift
//  Kobi
//
//  Phase 13 — live memory/CPU indicator for the canvas toolbar so users self-regulate before
//  hitting a ceiling. Each `WKWebView`'s page content actually runs in a separate
//  `com.apple.WebKit.WebContent` XPC process, not in this app's own process, so sampling our
//  own process would show near-zero regardless of how many device frames are open. Instead this
//  shells out to `ps` (the app is direct-distributed/non-sandboxed per docs/ROADMAP.md, so this
//  is available) and sums resident memory and %CPU across every WebContent process whose parent
//  is this app — the same technique Activity Monitor uses to attribute a multi-process app's
//  real footprint.
//

import Foundation
import Observation

@Observable
final class ResourceMonitor {
    private(set) var residentMemoryMB: Double = 0
    private(set) var cpuPercent: Double = 0
    private(set) var processCount: Int = 0

    private var timer: Timer?
    private var sampleTask: Task<Void, Never>?

    deinit {
        timer?.invalidate()
        sampleTask?.cancel()
    }

    func start(interval: TimeInterval = 2) {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sampleTask?.cancel()
        sampleTask = nil
    }

    private func sample() {
        sampleTask?.cancel()
        sampleTask = Task { [weak self] in
            guard let sample = await Self.sampleWebContentProcesses() else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.residentMemoryMB = sample.residentMemoryMB
                self?.cpuPercent = sample.cpuPercent
                self?.processCount = sample.processCount
            }
        }
    }

    private struct Sample {
        let residentMemoryMB: Double
        let cpuPercent: Double
        let processCount: Int
    }

    private static func sampleWebContentProcesses() async -> Sample? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pid=,ppid=,rss=,pcpu=,comm="]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return nil
            }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            let currentPID = ProcessInfo.processInfo.processIdentifier
            var totalRSSKilobytes: Double = 0
            var totalCPUPercent: Double = 0
            var count = 0

            for line in output.split(separator: "\n") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count >= 5,
                      let ppid = Int32(fields[1]), ppid == currentPID,
                      fields[4...].joined(separator: " ").contains("WebContent"),
                      let rss = Double(fields[2]),
                      let cpu = Double(fields[3])
                else { continue }
                totalRSSKilobytes += rss
                totalCPUPercent += cpu
                count += 1
            }

            return Sample(
                residentMemoryMB: totalRSSKilobytes / 1024,
                cpuPercent: totalCPUPercent,
                processCount: count
            )
        }.value
    }
}
