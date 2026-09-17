//
//  WorkspacesSheetView.swift
//  Kobi
//
//  Phase 6 — Workspace manager sheet: save, quick-switch, rename, and delete workspaces.
//

import SwiftUI

struct WorkspacesSheetView: View {
    let workspaceStore: WorkspaceStore
    let catalogStore: DeviceCatalogStore
    let isCanvasMode: Bool
    let singleDevice: Device?
    let singleURL: String?
    let canvasFrames: [SimulatorViewModel]
    let canvasPositions: [UUID: CGPoint]
    let canvasSharedURL: String
    let isSharedURLMode: Bool
    let isScrollSyncEnabled: Bool
    let onLoadWorkspace: (Workspace) -> Void
    let onDismiss: () -> Void

    @State private var newWorkspaceName = ""
    @State private var isShowingSaveField = false
    @State private var renamingWorkspaceID: UUID?
    @State private var editingName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            saveCurrentSection
            Divider()
            workspaceList
        }
        .frame(width: 520, height: 500)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("workspace.title")
                    .font(.headline)
                Text("workspace.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("export.dismissHelp")
            .accessibilityLabel("export.dismissHelp")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var saveCurrentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("workspace.saveCurrent.title", systemImage: "plus.square.fill.on.square.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingSaveField.toggle()
                        if isShowingSaveField {
                            newWorkspaceName = defaultWorkspaceName
                        }
                    }
                } label: {
                    Text(isShowingSaveField ? "workspace.button.cancel" : "workspace.button.new")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if isShowingSaveField {
                HStack(spacing: 8) {
                    TextField("workspace.name.placeholder", text: $newWorkspaceName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveCurrentLayout() }

                    Button {
                        saveCurrentLayout()
                    } label: {
                        Text("workspace.button.save")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KobiTheme.primaryAccent)
                    .disabled(newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            // Current layout summary chip
            HStack(spacing: 6) {
                Image(systemName: isCanvasMode ? "square.grid.2x2" : "iphone")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(currentLayoutSummary)
                    .telemetryFont(size: 11)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var currentLayoutSummary: String {
        if isCanvasMode {
            let count = canvasFrames.count
            let deviceWord = count == 1
                ? String(localized: "workspace.summary.deviceSingular")
                : String(localized: "workspace.summary.devicePlural")
            return String(localized: "workspace.summary.canvas \(count) \(deviceWord) \(canvasSharedURL)")
        } else if let singleDevice {
            return String(
                localized: "workspace.summary.single \(singleDevice.name) \(singleURL ?? "http://localhost:3000")"
            )
        } else {
            return String(localized: "workspace.summary.empty")
        }
    }

    private var defaultWorkspaceName: String {
        if isCanvasMode {
            let names = canvasFrames.prefix(2).map(\.device.name).joined(separator: " & ")
            return names.isEmpty
                ? String(localized: "workspace.summary.canvasLayoutDefault")
                : String(localized: "workspace.summary.namedWorkspace \(names)")
        } else if let singleDevice {
            return String(localized: "workspace.summary.namedWorkspace \(singleDevice.name)")
        }
        return String(localized: "workspace.summary.myWorkspaceDefault")
    }

    private func saveCurrentLayout() {
        let name = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let frameItems: [WorkspaceFrameItem] = canvasFrames.map { frame in
            let pos = canvasPositions[frame.id] ?? CGPoint(x: 180, y: 290)
            return WorkspaceFrameItem(
                id: UUID(),
                deviceID: frame.device.id,
                urlString: frame.urlString,
                orientation: frame.orientation,
                positionX: Double(pos.x),
                positionY: Double(pos.y)
            )
        }

        let workspace = Workspace(
            name: name,
            isCanvasMode: isCanvasMode,
            singleDeviceID: singleDevice?.id,
            singleDeviceURL: singleURL,
            canvasFrames: frameItems,
            sharedURL: canvasSharedURL,
            isSharedURLMode: isSharedURLMode,
            isScrollSyncEnabled: isScrollSyncEnabled
        )
        workspaceStore.save(workspace)

        newWorkspaceName = ""
        isShowingSaveField = false
    }

    private var workspaceList: some View {
        List {
            ForEach(workspaceStore.workspaces) { ws in
                workspaceRow(ws)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func workspaceRow(_ ws: Workspace) -> some View {
        HStack(alignment: .center, spacing: 12) {
            workspaceInfo(for: ws)
            Spacer()
            workspaceActions(for: ws)
        }
        .padding(.vertical, 6)
    }

    private func workspaceInfo(for ws: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            workspaceTitleRow(for: ws)
            deviceChips(for: ws)
            Text(ws.isCanvasMode ? ws.sharedURL : (ws.singleDeviceURL ?? "http://localhost:3000"))
                .telemetryFont(size: 10)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func workspaceTitleRow(for ws: Workspace) -> some View {
        if renamingWorkspaceID == ws.id {
            HStack {
                TextField("workspace.name.placeholder", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        workspaceStore.rename(id: ws.id, newName: editingName)
                        renamingWorkspaceID = nil
                    }
                Button("workspace.button.done") {
                    workspaceStore.rename(id: ws.id, newName: editingName)
                    renamingWorkspaceID = nil
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        } else {
            HStack(spacing: 6) {
                Text(ws.name)
                    .font(.system(size: 13, weight: .semibold))

                Text(ws.isCanvasMode ? "workspace.badge.canvas" : "workspace.badge.single")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
    }

    private func workspaceActions(for ws: Workspace) -> some View {
        HStack(spacing: 8) {
            Button {
                onLoadWorkspace(ws)
                onDismiss()
            } label: {
                Label("workspace.button.open", systemImage: "arrow.up.right.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(KobiTheme.primaryAccent)

            Menu {
                Button("workspace.action.rename") {
                    editingName = ws.name
                    renamingWorkspaceID = ws.id
                }

                Divider()

                Button("workspace.action.delete", role: .destructive) {
                    workspaceStore.delete(id: ws.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func deviceChips(for ws: Workspace) -> some View {
        HStack(spacing: 4) {
            if ws.isCanvasMode {
                ForEach(ws.canvasFrames.prefix(3)) { frame in
                    let name = catalogStore.allDevices.first(where: { $0.id == frame.deviceID })?.name ?? frame.deviceID
                    Text(name)
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                if ws.canvasFrames.count > 3 {
                    Text("+\(ws.canvasFrames.count - 3)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else if let deviceID = ws.singleDeviceID {
                let name = catalogStore.allDevices.first(where: { $0.id == deviceID })?.name ?? deviceID
                Text(name)
                    .font(.system(size: 10))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
    }
}
