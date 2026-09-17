//
//  ExportSheetView.swift
//  Kobi
//
//  Export Device Mockup & Recording Sheet matching docs/UI_SPECIFICATION.md
//  Phase 7 — Localization & accessibility QA
//

import SwiftUI
import UniformTypeIdentifiers

enum ExportMode: String, CaseIterable, Identifiable {
    case snapshot
    case recording
    case blankMockup

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .snapshot: String(localized: "export.mode.snapshot")
        case .recording: String(localized: "export.mode.recording")
        case .blankMockup: String(localized: "export.mode.blankMockup")
        }
    }
}

enum ResolutionScale: Int, CaseIterable, Identifiable {
    case x1 = 1
    case x2 = 2
    case x3 = 3

    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .x1: String(localized: "export.resolution.x1")
        case .x2: String(localized: "export.resolution.x2")
        case .x3: String(localized: "export.resolution.x3")
        }
    }
}

enum RecordingFormat: String, CaseIterable, Identifiable {
    case mp4
    case gif

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .mp4: String(localized: "export.recordingFormat.mp4")
        case .gif: String(localized: "export.recordingFormat.gif")
        }
    }
}

struct ExportSheetView: View {
    @Bindable var viewModel: SimulatorViewModel
    let recordingRegion: RecordingRegion
    @Bindable var screenRecorder: ScreenRecorder
    let onDismiss: () -> Void

    @State private var exportMode: ExportMode = .snapshot
    @State private var includeFrame: Bool = true
    @State private var transparentBg: Bool = false
    @State private var resolutionScale: ResolutionScale = .x2
    @State private var recordingFormat: RecordingFormat = .mp4
    @State private var showCopiedAlert: Bool = false
    @State private var isBusy: Bool = false
    @State private var errorMessage: String?
    @State private var previewImage: NSImage?
    @State private var recordedFileURL: URL?

    private var device: Device {
        viewModel.device
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("export.mode.label", selection: $exportMode) {
                ForEach(ExportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(screenRecorder.isRecording)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            previewArea

            if let displayedError {
                Text(displayedError)
                    .font(.caption)
                    .foregroundStyle(KobiTheme.statusError)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            configurationControls

            Divider()
            actions
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .task(id: previewKey) {
            await generatePreview()
        }
        .onDisappear {
            if screenRecorder.isRecording {
                Task { try? await screenRecorder.stop() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("export.title")
                .font(.headline)

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

    // MARK: - Preview

    private var previewArea: some View {
        ZStack {
            CheckeredBackground()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )

            switch exportMode {
            case .snapshot, .blankMockup:
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 190)
                } else {
                    ProgressView()
                }
            case .recording:
                recordingPreview
            }
        }
        .padding(.horizontal, 20)
    }

    private var recordingPreview: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(screenRecorder.isRecording ? KobiTheme.statusError : Color.primary.opacity(0.15))
                    .frame(width: 14, height: 14)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }

            Text(screenRecorder.isRecording ? elapsedLabel : String(localized: "export.recording.ready"))
                .telemetryFont(size: 14, weight: .semibold)

            Text(device.name)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            if showCopiedAlert {
                Label("export.actions.copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(KobiTheme.statusOnline)
                    .font(.caption)
            }

            Spacer()

            switch exportMode {
            case .snapshot, .blankMockup:
                Button("export.actions.copy") {
                    Task { await copyImage() }
                }
                .disabled(isBusy || previewImage == nil)
                .keyboardShortcut("c", modifiers: .command)

                Button("export.actions.save") {
                    Task { await saveImage() }
                }
                .buttonStyle(.borderedProminent)
                .tint(KobiTheme.primaryAccent)
                .disabled(isBusy || previewImage == nil)
                .keyboardShortcut("s", modifiers: .command)

            case .recording:
                if recordedFileURL != nil, !screenRecorder.isRecording {
                    Button("export.actions.save") {
                        Task { await saveRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KobiTheme.primaryAccent)
                    .disabled(isBusy)
                    .keyboardShortcut("s", modifiers: .command)
                }

                Button(screenRecorder
                    .isRecording ? String(localized: "export.recording.stop") :
                    String(localized: "export.recording.start"))
                {
                    Task { await toggleRecording() }
                }
                .buttonStyle(.borderedProminent)
                .tint(screenRecorder.isRecording ? KobiTheme.statusError : KobiTheme.primaryAccent)
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Snapshot / Blank Mockup

    private var previewKey: String {
        "\(exportMode.rawValue)-\(includeFrame)-\(transparentBg)-\(device.id)-\(viewModel.orientation.rawValue)"
    }

    private func generatePreview() async {
        guard exportMode != .recording else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            switch exportMode {
            case .snapshot:
                guard let webView = viewModel.webView else {
                    errorMessage = String(localized: "export.error.noWebView")
                    return
                }
                let image = try await CaptureExporter.captureSnapshot(
                    webView: webView,
                    device: device,
                    orientation: viewModel.orientation,
                    includeFrame: includeFrame,
                    transparentBackground: transparentBg,
                    scale: 1.0
                )
                previewImage = image

            case .blankMockup:
                let image = try CaptureExporter.captureBlankMockup(
                    device: device,
                    orientation: viewModel.orientation,
                    includeFrame: includeFrame,
                    transparentBackground: transparentBg,
                    scale: 1.0
                )
                previewImage = image

            case .recording:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyImage() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let image = try await renderExportImage(scale: CGFloat(resolutionScale.rawValue))
            CaptureExporter.copyToClipboard(image)
            withAnimation { showCopiedAlert = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { showCopiedAlert = false }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveImage() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let image = try await renderExportImage(scale: CGFloat(resolutionScale.rawValue))
            let data = try CaptureExporter.pngData(from: image)
            let defaultName = "\(device.id)-\(exportMode.rawValue).png"
            _ = await CaptureExporter.save(data, suggestedName: defaultName, contentType: .png)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renderExportImage(scale: CGFloat) async throws -> NSImage {
        switch exportMode {
        case .snapshot:
            guard let webView = viewModel.webView else {
                throw CaptureExportError.snapshotFailed
            }
            return try await CaptureExporter.captureSnapshot(
                webView: webView,
                device: device,
                orientation: viewModel.orientation,
                includeFrame: includeFrame,
                transparentBackground: transparentBg,
                scale: scale
            )
        case .blankMockup:
            return try CaptureExporter.captureBlankMockup(
                device: device,
                orientation: viewModel.orientation,
                includeFrame: includeFrame,
                transparentBackground: transparentBg,
                scale: scale
            )
        case .recording:
            throw CaptureExportError.renderFailed
        }
    }

    // MARK: - Video / GIF Recording

    private func toggleRecording() async {
        if screenRecorder.isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        errorMessage = nil
        recordedFileURL = nil

        guard recordingRegion.window != nil, !recordingRegion.frameInWindow.isEmpty else {
            errorMessage = String(localized: "export.error.noRegion")
            return
        }

        do {
            try await screenRecorder.start(region: recordingRegion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let tempURL = try await screenRecorder.stop()
            switch recordingFormat {
            case .mp4:
                recordedFileURL = tempURL
            case .gif:
                let gifURL = try await GIFExporter.convert(
                    mp4URL: tempURL,
                    frameRate: 15,
                    maxDimension: 800
                )
                recordedFileURL = gifURL
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRecording() async {
        guard let fileURL = recordedFileURL else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let data = try Data(contentsOf: fileURL)
            let isGIF = recordingFormat == .gif
            let ext = isGIF ? "gif" : "mp4"
            let utType: UTType = isGIF ? .gif : .mpeg4Movie
            _ = await CaptureExporter.save(data, suggestedName: "\(device.id)-recording.\(ext)", contentType: utType)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var elapsedLabel: String {
        let seconds = Int(screenRecorder.elapsedSeconds)
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var displayedError: String? {
        errorMessage ?? screenRecorder.lastError
    }
}

// MARK: - Configuration Controls

//
// Split into its own extension (rather than kept inline in the main struct) purely to keep
// ExportSheetView's primary type body under this project's SwiftLint length limit — same file,
// same access to private members, identical behavior.

extension ExportSheetView {
    @ViewBuilder
    private var configurationControls: some View {
        switch exportMode {
        case .snapshot, .blankMockup:
            VStack(spacing: 12) {
                Toggle("export.options.includeFrame", isOn: $includeFrame)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("export.options.transparentBg", isOn: $transparentBg)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("export.resolution.label")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("export.resolution.label", selection: $resolutionScale) {
                        ForEach(ResolutionScale.allCases) { scale in
                            Text(scale.label).tag(scale)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .accessibilityLabel("export.resolution.label")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

        case .recording:
            HStack {
                Text("export.format.label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("export.format.label", selection: $recordingFormat) {
                    ForEach(RecordingFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                .disabled(screenRecorder.isRecording)
                .accessibilityLabel("export.format.label")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}
