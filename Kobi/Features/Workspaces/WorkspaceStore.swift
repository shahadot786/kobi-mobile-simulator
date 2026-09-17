//
//  WorkspaceStore.swift
//  Kobi
//
//  Phase 6 — Workspace persistence and management store.
//

import Foundation
import Observation

@Observable
final class WorkspaceStore {
    private static let storageKey = "kobi_saved_workspaces_v1"

    var workspaces: [Workspace] = []

    init() {
        loadWorkspaces()
    }

    func save(
        name: String,
        isCanvasMode: Bool,
        singleDeviceID: String?,
        singleDeviceURL: String?,
        canvasFrames: [WorkspaceFrameItem],
        sharedURL: String,
        isSharedURLMode: Bool,
        isScrollSyncEnabled: Bool
    ) -> Workspace {
        let workspace = Workspace(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "workspace.untitled")
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            isCanvasMode: isCanvasMode,
            singleDeviceID: singleDeviceID,
            singleDeviceURL: singleDeviceURL,
            canvasFrames: canvasFrames,
            sharedURL: sharedURL,
            isSharedURLMode: isSharedURLMode,
            isScrollSyncEnabled: isScrollSyncEnabled,
            createdAt: Date()
        )
        workspaces.insert(workspace, at: 0)
        persist()
        return workspace
    }

    func delete(id: UUID) {
        workspaces.removeAll { $0.id == id }
        persist()
    }

    func rename(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = trimmed
        persist()
    }

    private func loadWorkspaces() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data),
           !decoded.isEmpty
        {
            workspaces = decoded
            return
        }
        // Provide built-in starter presets if no saved workspaces exist yet
        workspaces = Self.defaultPresets()
        persist()
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }

    private static func defaultPresets() -> [Workspace] {
        [
            Workspace(
                name: String(localized: "workspace.preset.mobileTabletPair"),
                isCanvasMode: true,
                canvasFrames: [
                    WorkspaceFrameItem(
                        deviceID: "iphone-15-pro",
                        urlString: "http://localhost:3000",
                        positionX: 180,
                        positionY: 290
                    ),
                    WorkspaceFrameItem(
                        deviceID: "ipad-air-11-m2",
                        urlString: "http://localhost:3000",
                        positionX: 520,
                        positionY: 290
                    ),
                ],
                sharedURL: "http://localhost:3000",
                isSharedURLMode: true,
                isScrollSyncEnabled: true
            ),
            Workspace(
                name: String(localized: "workspace.preset.modernFlagships"),
                isCanvasMode: true,
                canvasFrames: [
                    WorkspaceFrameItem(
                        deviceID: "iphone-15-pro",
                        urlString: "http://localhost:3000",
                        positionX: 180,
                        positionY: 290
                    ),
                    WorkspaceFrameItem(
                        deviceID: "samsung-galaxy-s24",
                        urlString: "http://localhost:3000",
                        positionX: 480,
                        positionY: 290
                    ),
                    WorkspaceFrameItem(
                        deviceID: "google-pixel-8",
                        urlString: "http://localhost:3000",
                        positionX: 780,
                        positionY: 290
                    ),
                ],
                sharedURL: "http://localhost:3000",
                isSharedURLMode: true,
                isScrollSyncEnabled: true
            ),
        ]
    }
}
