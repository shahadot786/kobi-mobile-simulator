//
//  DevToolsModels.swift
//  Kobi
//
//  Phase 10 — Debugger & DevTools panel: console/JS-error and network log entries.
//

import Foundation

enum ConsoleLogLevel: String {
    case log
    case info
    case warn
    case error
}

struct ConsoleLogEntry: Identifiable, Equatable {
    let id = UUID()
    let level: ConsoleLogLevel
    let message: String
    let timestamp: Date
}

struct NetworkLogEntry: Identifiable, Equatable {
    let id = UUID()
    let method: String
    let path: String
    let statusCode: Int?
    let durationMilliseconds: Double
    let byteCount: Int
    let timestamp: Date
}

/// Core Web Vitals-style timing plus a lightweight, count-based a11y pass — Phase 16. Not a
/// full Lighthouse port: the a11y checks are structural presence checks (missing alt/label),
/// not full WCAG contrast/semantics analysis.
struct PerfMetricsSnapshot: Equatable {
    let timeToFirstByteMilliseconds: Double?
    let domContentLoadedMilliseconds: Double?
    let loadMilliseconds: Double?
    let largestContentfulPaintMilliseconds: Double?
    let cumulativeLayoutShift: Double?
    let imagesMissingAltCount: Int
    let buttonsMissingLabelCount: Int
    let inputsMissingLabelCount: Int
}

/// The computed box model for a clicked element in element-inspector mode — Phase 16.
struct ElementBoxModel: Equatable {
    let tagName: String
    let elementID: String?
    let className: String?
    let width: Double
    let height: Double
    let margin: String
    let border: String
    let padding: String
    let fontSize: String
    let color: String
}
