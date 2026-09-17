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
