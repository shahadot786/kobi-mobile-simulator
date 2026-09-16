//
//  Workspace.swift
//  Kobi
//
//  Phase 6 — Named device + URL layout configurations for quick-switch recall.
//

import Foundation

struct WorkspaceFrameItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var deviceID: String
    var urlString: String
    var orientation: DeviceOrientation
    var positionX: Double
    var positionY: Double

    init(
        id: UUID = UUID(),
        deviceID: String,
        urlString: String = "http://localhost:3000",
        orientation: DeviceOrientation = .portrait,
        positionX: Double = 0,
        positionY: Double = 0
    ) {
        self.id = id
        self.deviceID = deviceID
        self.urlString = urlString
        self.orientation = orientation
        self.positionX = positionX
        self.positionY = positionY
    }
}

struct Workspace: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isCanvasMode: Bool
    var singleDeviceID: String?
    var singleDeviceURL: String?
    var canvasFrames: [WorkspaceFrameItem]
    var sharedURL: String
    var isSharedURLMode: Bool
    var isScrollSyncEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isCanvasMode: Bool = true,
        singleDeviceID: String? = nil,
        singleDeviceURL: String? = nil,
        canvasFrames: [WorkspaceFrameItem] = [],
        sharedURL: String = "http://localhost:3000",
        isSharedURLMode: Bool = true,
        isScrollSyncEnabled: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isCanvasMode = isCanvasMode
        self.singleDeviceID = singleDeviceID
        self.singleDeviceURL = singleDeviceURL
        self.canvasFrames = canvasFrames
        self.sharedURL = sharedURL
        self.isSharedURLMode = isSharedURLMode
        self.isScrollSyncEnabled = isScrollSyncEnabled
        self.createdAt = createdAt
    }
}
