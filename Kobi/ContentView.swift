//
//  ContentView.swift
//  Kobi
//

import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case single
    case canvas
    case mockups

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .single: "contentView.mode.single"
        case .canvas: "contentView.mode.canvas"
        case .mockups: "contentView.mode.mockups"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var catalogStore = DeviceCatalogStore()
    @State private var simulatorViewModel: SimulatorViewModel?
    @State private var canvasViewModel = CanvasViewModel()
    @State private var viewMode: ViewMode = .single
    @State private var mockupDeviceIDs: Set<String> = []

    var body: some View {
        NavigationSplitView {
            DevicePickerView(
                store: catalogStore,
                isSelected: isDeviceSelected,
                onSelect: selectDevice
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            VStack(spacing: 0) {
                topBar
                Divider()
                switch viewMode {
                case .single:
                    if let simulatorViewModel {
                        SimulatorView(viewModel: simulatorViewModel)
                    } else {
                        emptyState
                    }
                case .canvas:
                    CanvasView(canvasViewModel: canvasViewModel)
                case .mockups:
                    MockupLibraryView(
                        devices: catalogStore.allDevices.filter { mockupDeviceIDs.contains($0.id) },
                        onRemove: { mockupDeviceIDs.remove($0.id) },
                        onSelectAllFiltered: {
                            for device in catalogStore.filteredDevices { mockupDeviceIDs.insert(device.id) }
                        },
                        onClearSelection: { mockupDeviceIDs.removeAll() }
                    )
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            if simulatorViewModel == nil {
                let devices = catalogStore.allDevices
                if let device = devices.first(where: { $0.id == "iphone-15-pro" }) ?? devices.first {
                    simulatorViewModel = SimulatorViewModel(device: device)
                }
            }

            if !appState.hasCompletedOnboarding {
                appState.isOnboardingPresented = true
            }
        }
        .sheet(isPresented: Bindable(appState).isOnboardingPresented) {
            OnboardingView(
                catalogStore: catalogStore,
                onComplete: { selectedDevice, initialURL in
                    appState.hasCompletedOnboarding = true
                    appState.isOnboardingPresented = false
                    selectDevice(selectedDevice)
                    simulatorViewModel?.load(urlString: initialURL)
                    canvasViewModel.sharedURLString = initialURL
                },
                onDismiss: {
                    appState.hasCompletedOnboarding = true
                    appState.isOnboardingPresented = false
                }
            )
        }
        .sheet(isPresented: Bindable(appState).isWorkspacesSheetPresented) {
            WorkspacesSheetView(
                workspaceStore: appState.workspaceStore,
                catalogStore: catalogStore,
                isCanvasMode: viewMode == .canvas,
                singleDevice: simulatorViewModel?.device,
                singleURL: simulatorViewModel?.urlString,
                canvasFrames: canvasViewModel.frames,
                canvasPositions: canvasViewModel.framePositions,
                canvasSharedURL: canvasViewModel.sharedURLString,
                isSharedURLMode: canvasViewModel.isSharedURLMode,
                isScrollSyncEnabled: canvasViewModel.isScrollSyncEnabled,
                onLoadWorkspace: { workspace in
                    loadWorkspace(workspace)
                },
                onDismiss: {
                    appState.isWorkspacesSheetPresented = false
                }
            )
        }
        // Menu & Global Shortcuts Handlers
        .onChange(of: appState.triggerRotateOrientation) { _, _ in
            simulatorViewModel?.toggleOrientation()
        }
        .onChange(of: appState.triggerToggleFrame) { _, _ in
            simulatorViewModel?.isFrameVisible.toggle()
        }
        .onChange(of: appState.triggerReload) { _, _ in
            if viewMode == .canvas {
                canvasViewModel.broadcastSharedURL()
            } else {
                simulatorViewModel?.reload()
            }
        }
        .onChange(of: appState.triggerZoomFit) { _, _ in
            simulatorViewModel?.zoomOption = .fit
        }
        .onChange(of: appState.pendingWorkspaceID) { _, workspaceID in
            guard let workspaceID,
                  let workspace = appState.workspaceStore.workspaces.first(where: { $0.id == workspaceID })
            else { return }
            loadWorkspace(workspace)
            appState.pendingWorkspaceID = nil
        }
        .background {
            // Invisible shortcut listeners for view switching and workspaces
            Group {
                Button("") { viewMode = .single }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { viewMode = .canvas }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { viewMode = .mockups }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { appState.isWorkspacesSheetPresented.toggle() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            modePicker
            Spacer()
            Button {
                appState.isWorkspacesSheetPresented = true
            } label: {
                Label("workspace.toolbar.button", systemImage: "square.stack.3d.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help("workspace.toolbar.help")
            .padding(.trailing, 12)
        }
        .padding(.vertical, 4)
    }

    private var modePicker: some View {
        Picker("contentView.mode.picker", selection: $viewMode) {
            ForEach(ViewMode.allCases) { mode in
                Text(mode.titleKey).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.vertical, 4)
        .fixedSize()
    }

    private func isDeviceSelected(_ device: Device) -> Bool {
        switch viewMode {
        case .single: device.id == simulatorViewModel?.device.id
        case .canvas: canvasViewModel.isOpen(device)
        case .mockups: mockupDeviceIDs.contains(device.id)
        }
    }

    /// Mutates the existing view model's device in place rather than creating a new
    /// `SimulatorViewModel` — that keeps the same `WKWebView` instance alive, so switching
    /// devices doesn't reload the page or lose navigation state.
    private func selectDevice(_ device: Device) {
        switch viewMode {
        case .single:
            if let simulatorViewModel {
                simulatorViewModel.device = device
            } else {
                simulatorViewModel = SimulatorViewModel(device: device)
            }
        case .canvas:
            canvasViewModel.toggleFrame(for: device)
        case .mockups:
            if mockupDeviceIDs.contains(device.id) {
                mockupDeviceIDs.remove(device.id)
            } else {
                mockupDeviceIDs.insert(device.id)
            }
        }
    }

    private func loadWorkspace(_ workspace: Workspace) {
        if workspace.isCanvasMode {
            viewMode = .canvas
            canvasViewModel.clearAllFrames()
            canvasViewModel.sharedURLString = workspace.sharedURL
            canvasViewModel.isSharedURLMode = workspace.isSharedURLMode
            canvasViewModel.isScrollSyncEnabled = workspace.isScrollSyncEnabled

            for item in workspace.canvasFrames {
                if let device = catalogStore.allDevices.first(where: { $0.id == item.deviceID }) {
                    canvasViewModel.addFrame(
                        for: device,
                        urlString: item.urlString,
                        orientation: item.orientation,
                        position: CGPoint(x: item.positionX, y: item.positionY)
                    )
                }
            }
        } else {
            viewMode = .single
            if let deviceID = workspace.singleDeviceID,
               let device = catalogStore.allDevices.first(where: { $0.id == deviceID }) {
                if let existing = simulatorViewModel {
                    existing.device = device
                    if let url = workspace.singleDeviceURL {
                        existing.load(urlString: url)
                    }
                } else {
                    simulatorViewModel = SimulatorViewModel(
                        device: device,
                        initialURLString: workspace.singleDeviceURL ?? "http://localhost:3000"
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("app.mainWindow.hello")
                .font(.title2)
            Text("app.mainWindow.noDevices")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
