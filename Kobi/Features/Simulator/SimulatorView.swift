//
//  SimulatorView.swift
//  Kobi
//
//  Phase 1 — Single device simulator view
//  Phase 3 — Hardware chassis framing & studio dot-grid canvas
//  Phase 4 — Screenshot, video recording, and mockup export
//  Phase 5 — Simulation depth: Touch/Gesture, Network Throttling, Kiosk/PWA mode, Media Query Cheat Sheet
//  Phase 7 — Accessibility, smart error states, and localization QA
//

import SwiftUI
import UniformTypeIdentifiers

struct SimulatorView: View {
    @Bindable var viewModel: SimulatorViewModel
    @Environment(AppState.self) private var appState

    // Export Sheet & Media Query Sheet
    @State private var isExportSheetPresented = false
    @State private var isMediaQuerySheetPresented = false
    @State private var screenRecorder = ScreenRecorder()
    @State private var recordingRegion = RecordingRegion()

    @FocusState private var isURLBarFocused: Bool

    // Watch mode (auto-reload on save)
    @State private var isWatchModeEnabled = false

    // Visual feedback for DPR breakpoint copy
    @State private var copiedCSSFeedback = false

    var body: some View {
        Group {
            if viewModel.isKioskModeEnabled {
                kioskModeBody
            } else {
                standardBody
            }
        }
        .sheet(isPresented: $isExportSheetPresented) {
            ExportSheetView(
                viewModel: viewModel,
                recordingRegion: recordingRegion,
                screenRecorder: screenRecorder,
                onDismiss: { isExportSheetPresented = false }
            )
        }
        .sheet(isPresented: $isMediaQuerySheetPresented) {
            MediaQueryCheatSheetView(
                currentDeviceName: viewModel.device.name,
                currentDeviceWidth: viewModel.device.viewportWidth,
                onDismiss: { isMediaQuerySheetPresented = false }
            )
        }
        .onChange(of: appState.triggerFocusURLBar) { _, _ in
            isURLBarFocused = true
        }
        .onChange(of: appState.triggerExportSheet) { _, _ in
            isExportSheetPresented = true
        }
    }

    // MARK: - Standard Simulator Presentation

    private var standardBody: some View {
        VStack(spacing: 0) {
            precisionToolbar
            Divider()
            canvas
            Divider()
            telemetryStatusBar
        }
    }

    // MARK: - Kiosk / PWA Presentation (Phase 5)

    private var kioskModeBody: some View {
        ZStack(alignment: .topTrailing) {
            KobiTheme.canvasBase
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        DeviceFrameView(
                            device: viewModel.device,
                            orientation: viewModel.orientation,
                            isFrameVisible: viewModel.isFrameVisible
                        ) {
                            WebViewRepresentable(viewModel: viewModel)
                        }
                        .scaleEffect(scale(in: proxy.size))
                        .frame(
                            width: naturalSize.width * scale(in: proxy.size),
                            height: naturalSize.height * scale(in: proxy.size)
                        )
                    }
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isKioskModeEnabled = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("simulator.kiosk.exit")
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(16)
            .keyboardShortcut(.escape, modifiers: [])
            .help("simulator.kiosk.exitHelp")
        }
    }

    // MARK: - Precision macOS Toolbar

    private var precisionToolbar: some View {
        HStack(spacing: 8) {
            // Web History Navigation Cluster
            HStack(spacing: 2) {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(!viewModel.canGoBack)
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("accessibility.navigation.back")

                Button {
                    viewModel.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(!viewModel.canGoForward)
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("accessibility.navigation.forward")

                Button {
                    viewModel.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("accessibility.navigation.reload")
            }

            // Styled Precision URL Bar
            HStack(spacing: 6) {
                Image(systemName: isLocalhost ? "desktopcomputer" : "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField("simulator.urlBar.placeholder", text: $viewModel.urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isURLBarFocused)
                    .onSubmit { viewModel.submitURL() }
                    .accessibilityLabel("accessibility.simulator.urlBar")

                if let port = detectedPort {
                    Text(verbatim: "Dev: \(port)")
                        .telemetryFont(size: 9, weight: .semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(KobiTheme.primaryAccent.opacity(0.12))
                        .foregroundStyle(KobiTheme.primaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                // Watch Mode Toggle Pill
                Button {
                    isWatchModeEnabled.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("simulator.toolbar.watch")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isWatchModeEnabled ? KobiTheme.statusOnline.opacity(0.15) : Color.primary.opacity(0.05))
                    .foregroundStyle(isWatchModeEnabled ? KobiTheme.statusOnline : .secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("simulator.toolbar.watchHelp")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Zoom Controller
            Menu {
                ForEach(ZoomOption.allCases) { option in
                    Button {
                        viewModel.zoomOption = option
                    } label: {
                        if option == viewModel.zoomOption {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(verbatim: option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                    Text(verbatim: viewModel.zoomOption.label)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("simulator.toolbar.zoom")
            .accessibilityLabel("accessibility.simulator.zoom")

            Divider().frame(height: 18)

            // Orientation Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.toggleOrientation()
                }
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help("simulator.toolbar.orientation")
            .accessibilityLabel("accessibility.simulator.orientationToggle")

            // Frame On/Off Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isFrameVisible.toggle()
                }
            } label: {
                Image(systemName: viewModel.isFrameVisible ? "iphone" : "rectangle")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help("simulator.toolbar.frameToggle")
            .accessibilityLabel("accessibility.simulator.frameToggle")

            // Simulation Menu
            Menu {
                Section("simulator.menu.network") {
                    ForEach(NetworkThrottlePreset.allCases) { preset in
                        Button {
                            viewModel.networkThrottlePreset = preset
                        } label: {
                            if preset == viewModel.networkThrottlePreset {
                                Label(preset.label, systemImage: "checkmark")
                            } else {
                                Text(preset.label)
                            }
                        }
                    }
                }

                Divider()

                Toggle("simulator.menu.touchSimulation", isOn: $viewModel.isTouchSimulationEnabled)
                Toggle("simulator.menu.keyboardOverlay", isOn: $viewModel.isKeyboardOverlayEnabled)
                Toggle("simulator.menu.kioskMode", isOn: $viewModel.isKioskModeEnabled)

                Divider()

                Button("simulator.menu.mediaQuery") {
                    isMediaQuerySheetPresented = true
                }
            } label: {
                Label("simulator.menu.simulate", systemImage: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .medium))
            }
            .help("simulator.toolbar.simulateHelp")
            .accessibilityLabel("accessibility.simulator.simulationMenu")

            // Primary Export Action Button
            Button {
                isExportSheetPresented = true
            } label: {
                Label("simulator.toolbar.export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(KobiTheme.primaryAccent)
            .help("simulator.toolbar.exportHelp")
            .accessibilityLabel("accessibility.simulator.exportButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Canvas with Dot Grid & Viewport

    private var canvas: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    KobiTheme.canvasBase

                    // Dot Grid Underlay
                    StudioDotGridCanvas()

                    DeviceFrameView(
                        device: viewModel.device,
                        orientation: viewModel.orientation,
                        isFrameVisible: viewModel.isFrameVisible
                    ) {
                        WebViewRepresentable(viewModel: viewModel)
                    }
                    .scaleEffect(scale(in: proxy.size))
                    .frame(
                        width: naturalSize.width * scale(in: proxy.size),
                        height: naturalSize.height * scale(in: proxy.size)
                    )
                    .background(FrameRegionReader(region: recordingRegion))

                    if let error = viewModel.loadError {
                        errorOverlay(message: error)
                    }
                }
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
    }

    // MARK: - Developer Telemetry Status Bar

    private var telemetryStatusBar: some View {
        HStack(spacing: 16) {
            // Viewport Dimensions (Tabular Monospace)
            HStack(spacing: 4) {
                Text("simulator.telemetry.viewport")
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(viewModel.device.viewportWidth) × \(viewModel.device.viewportHeight) px")
                    .telemetryFont()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(String(localized: "accessibility.telemetry.viewport")): \(viewModel.device.viewportWidth) by \(viewModel.device.viewportHeight)")

            // DPR Badge with Copy Breakpoint Action
            Button {
                copyMediaBreakpoint()
            } label: {
                HStack(spacing: 3) {
                    Text(verbatim: "\(formattedDPR)× DPR")
                        .telemetryFont(size: 10, weight: .semibold)
                    if copiedCSSFeedback {
                        Text("simulator.toolbar.copied")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(KobiTheme.statusOnline)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("simulator.telemetry.copyDPRHelp")
            .accessibilityLabel("\(String(localized: "accessibility.telemetry.dpr")): \(formattedDPR)")

            // Latency & Network Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.loadError == nil ? KobiTheme.statusOnline : KobiTheme.statusError)
                    .frame(width: 6, height: 6)

                Text(viewModel.loadError == nil ? "simulator.status.online" : "simulator.status.offline")
                    .telemetryFont(size: 10)
                    .foregroundStyle(viewModel.loadError == nil ? .secondary : KobiTheme.statusError)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.loadError == nil ? String(localized: "simulator.status.online") : String(localized: "simulator.status.offline"))

            if viewModel.networkThrottlePreset != .none {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 9))
                    Text(viewModel.networkThrottlePreset.label)
                        .telemetryFont(size: 10)
                }
                .foregroundStyle(KobiTheme.statusWarning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(KobiTheme.statusWarning.opacity(0.12))
                .clipShape(Capsule())
                .accessibilityLabel(String(localized: "accessibility.status.throttle") + ": \(viewModel.networkThrottlePreset.label)")
            }

            if viewModel.isTouchSimulationEnabled {
                Label("simulator.status.touch", systemImage: "hand.tap")
                    .telemetryFont(size: 10)
                    .foregroundStyle(KobiTheme.primaryAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KobiTheme.primaryAccent.opacity(0.12))
                    .clipShape(Capsule())
            }

            if viewModel.isKeyboardOverlayEnabled && viewModel.isKeyboardOverlayVisible {
                Label("simulator.status.keyboardOverlay", systemImage: "keyboard")
                    .telemetryFont(size: 10)
                    .foregroundStyle(KobiTheme.primaryAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KobiTheme.primaryAccent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer()

            // Active Device & Orientation
            HStack(spacing: 6) {
                Text(viewModel.device.name)
                    .fontWeight(.medium)
                Text(viewModel.orientation == .portrait ? "simulator.orientation.portrait" : "simulator.orientation.landscape")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(viewModel.device.name), \(viewModel.orientation == .portrait ? String(localized: "simulator.orientation.portrait") : String(localized: "simulator.orientation.landscape"))")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func copyMediaBreakpoint() {
        let css = "@media (max-width: \(viewModel.device.viewportWidth)px) and (-webkit-min-device-pixel-ratio: \(formattedDPR))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(css, forType: .string)
        withAnimation {
            copiedCSSFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                copiedCSSFeedback = false
            }
        }
    }

    private var isLocalhost: Bool {
        viewModel.urlString.contains("localhost") || viewModel.urlString.contains("127.0.0.1")
    }

    private var detectedPort: String? {
        guard let url = URL(string: viewModel.urlString), let port = url.port else {
            if let match = viewModel.urlString.range(of: #":(\d{2,5})"#, options: .regularExpression) {
                return String(viewModel.urlString[match].dropFirst())
            }
            return nil
        }
        return String(port)
    }

    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: isLocalhost ? "laptopcomputer.trianglebadge.exclamationmark" : "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(isLocalhost ? KobiTheme.statusWarning : .secondary)

            Text(isLocalhost ? "simulator.error.localhostTitle" : "simulator.error.title")
                .font(.headline)

            Text(isLocalhost ? "simulator.error.localhostSubtitle" : LocalizedStringKey(message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button("simulator.error.retry") {
                viewModel.reload()
            }
            .buttonStyle(.borderedProminent)
            .tint(KobiTheme.primaryAccent)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var naturalSize: CGSize {
        DeviceFrameMetrics.naturalSize(
            device: viewModel.device,
            orientation: viewModel.orientation,
            frameVisible: viewModel.isFrameVisible
        )
    }

    private func scale(in size: CGSize) -> CGFloat {
        switch viewModel.zoomOption {
        case .fit:
            let horizontalScale = (size.width - 48) / naturalSize.width
            let verticalScale = (size.height - 48) / naturalSize.height
            return max(min(horizontalScale, verticalScale, 1.0), 0.1)
        case .percent50:
            return 0.5
        case .percent75:
            return 0.75
        case .percent100:
            return 1.0
        case .percent125:
            return 1.25
        case .percent150:
            return 1.5
        }
    }

    private var formattedDPR: String {
        let dpr = viewModel.device.pixelRatio
        return dpr.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", dpr) : String(format: "%.1f", dpr)
    }
}
