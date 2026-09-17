//
//  CanvasFrameCell.swift
//  Kobi
//
//  Phase 14 — per-frame recording: each cell gets its own `ScreenRecorder` + `RecordingRegion`
//  (rather than the single shared region single-device mode uses), so recordings on different
//  frames don't interfere with each other.
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasFrameCell: View {
    @Bindable var frame: SimulatorViewModel
    let isSharedURLMode: Bool
    let onRemove: () -> Void
    let isBeingDragged: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    private let cellHeight: CGFloat = 420
    private let keyboardMoveStep: CGFloat = 20

    @State private var isDevToolsPresented = false
    @State private var screenRecorder = ScreenRecorder()
    @State private var recordingRegion = RecordingRegion()
    @State private var recordingError: String?

    var body: some View {
        VStack(spacing: 6) {
            header

            if !isSharedURLMode {
                TextField("simulator.urlBar.placeholder", text: $frame.urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { frame.submitURL() }
            }

            if let recordingError {
                Text(recordingError)
                    .font(.caption2)
                    .foregroundStyle(KobiTheme.statusError)
                    .lineLimit(2)
            }

            ZStack(alignment: .topLeading) {
                DeviceFrameView(
                    device: frame.device,
                    orientation: frame.orientation,
                    isFrameVisible: frame.isFrameVisible
                ) {
                    WebViewRepresentable(viewModel: frame)
                }
                .scaleEffect(scale)
                .frame(width: naturalSize.width * scale, height: naturalSize.height * scale)
                .background(FrameRegionReader(region: recordingRegion))

                if screenRecorder.isRecording {
                    recordingBadge
                }

                if let error = frame.loadError {
                    errorOverlay(message: error)
                }
            }
            .frame(height: cellHeight)
            // Phase 13 — lazy-suspend: a low threshold means a card is only suspended once
            // almost entirely scrolled out, avoiding flicker right at the viewport edge.
            .kobiLazySuspend { isVisible in
                if isVisible {
                    frame.resume()
                } else {
                    frame.suspend()
                }
            }
        }
        .padding(10)
        .frame(width: CanvasViewModel.cardSize.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(isBeingDragged ? 0.35 : 0), radius: 16, y: 8)
        .scaleEffect(isBeingDragged ? 1.03 : 1)
        .opacity(isBeingDragged ? 0.9 : 1)
        .animation(.interactiveSpring(), value: isBeingDragged)
        .sheet(isPresented: $isDevToolsPresented) {
            DevToolsPanelView(viewModel: frame, onDismiss: { isDevToolsPresented = false })
        }
    }

    private var recordingBadge: some View {
        Text("canvas.frame.recordingBadge")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(KobiTheme.statusError, in: Capsule())
            .padding(6)
            .accessibilityLabel("\(String(localized: "canvas.frame.recordingBadge")): \(frame.device.name)")
    }

    private var header: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .gesture(
                    // Translation-only drag: no coordinate space / hit-testing against other
                    // cards needed — the card just follows the cursor freely and lands wherever
                    // it's released. See `CanvasViewModel.setPosition`.
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            onDragChanged(value.translation)
                        }
                        .onEnded { value in
                            onDragEnded(value.translation)
                        }
                )
                .focusable(true)
                .onKeyPress(.leftArrow) { move(dx: -keyboardMoveStep, dy: 0) }
                .onKeyPress(.rightArrow) { move(dx: keyboardMoveStep, dy: 0) }
                .onKeyPress(.upArrow) { move(dx: 0, dy: -keyboardMoveStep) }
                .onKeyPress(.downArrow) { move(dx: 0, dy: keyboardMoveStep) }
                .help("canvas.frame.dragHint")
                .accessibilityLabel("\(String(localized: "canvas.frame.moveLabel")): \(frame.device.name)")
                .accessibilityHint("canvas.frame.moveHint")
                .accessibilityActions {
                    Button("canvas.frame.moveLeft") { move(dx: -keyboardMoveStep, dy: 0) }
                    Button("canvas.frame.moveRight") { move(dx: keyboardMoveStep, dy: 0) }
                    Button("canvas.frame.moveUp") { move(dx: 0, dy: -keyboardMoveStep) }
                    Button("canvas.frame.moveDown") { move(dx: 0, dy: keyboardMoveStep) }
                }

            Text(frame.device.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if frame.jsErrorCount > 0 {
                Button {
                    isDevToolsPresented = true
                } label: {
                    Text(verbatim: "\(min(frame.jsErrorCount, 99))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(KobiTheme.statusError, in: Circle())
                }
                .buttonStyle(.plain)
                .help("simulator.toolbar.devToolsHelp")
                .accessibilityLabel("accessibility.simulator.devTools")
            }

            Spacer()

            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: screenRecorder.isRecording ? "stop.circle.fill" : "record.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(screenRecorder.isRecording ? KobiTheme.statusError : .secondary)
            .help("canvas.frame.recordHelp")
            .accessibilityLabel(
                screenRecorder.isRecording
                    ? String(localized: "canvas.frame.stopRecording") : String(localized: "canvas.frame.startRecording")
            )

            Button {
                frame.toggleOrientation()
            } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.plain)
            .help("simulator.toolbar.orientation")

            Button {
                frame.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("simulator.toolbar.reload")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("canvas.frame.remove")
        }
    }

    private func toggleRecording() async {
        if screenRecorder.isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        recordingError = nil
        guard recordingRegion.window != nil, !recordingRegion.frameInWindow.isEmpty else {
            recordingError = String(localized: "export.error.noRegion")
            return
        }
        do {
            try await screenRecorder.start(region: recordingRegion)
        } catch {
            recordingError = error.localizedDescription
        }
    }

    private func stopRecording() async {
        do {
            let tempURL = try await screenRecorder.stop()
            _ = await CaptureExporter.save(
                fileAt: tempURL,
                suggestedName: "\(frame.device.id)-recording.mp4",
                contentType: .mpeg4Movie
            )
        } catch {
            recordingError = error.localizedDescription
        }
    }

    @discardableResult
    private func move(dx: CGFloat, dy: CGFloat) -> KeyPress.Result {
        onDragEnded(CGSize(width: dx, height: dy))
        return .handled
    }

    private var naturalSize: CGSize {
        DeviceFrameMetrics.naturalSize(
            device: frame.device,
            orientation: frame.orientation,
            frameVisible: frame.isFrameVisible
        )
    }

    private var scale: CGFloat {
        guard naturalSize.height > 0 else { return 1 }
        return min(cellHeight / naturalSize.height, 1.5)
    }

    private func errorOverlay(message _: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text("simulator.error.title")
                .font(.caption.weight(.medium))
            Button("simulator.error.retry") {
                frame.reload()
            }
            .font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension View {
    /// `onScrollVisibilityChange` is macOS 15+; this project's deployment target is macOS 14
    /// (see docs/ROADMAP.md), so lazy-suspend degrades to a no-op on 14 rather than gating the
    /// whole app on a newer OS for one performance optimization.
    @ViewBuilder
    func kobiLazySuspend(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(macOS 15.0, *) {
            onScrollVisibilityChange(threshold: 0.1, action)
        } else {
            self
        }
    }
}
