//
//  CanvasView.swift
//  Kobi
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasView: View {
    @Bindable var canvasViewModel: CanvasViewModel
    @Environment(AppState.self) private var appState
    @State private var isExportingCanvas = false
    @State private var canvasExportError: String?
    @State private var showCanvasCopiedAlert = false
    @FocusState private var isSharedURLFieldFocused: Bool

    // Freeform placement — each card has its own (x, y) on a large pannable canvas
    // (`CanvasViewModel.canvasSize`); dragging just moves the card to wherever it's released,
    // with no grid slots to swap into and no snapping against other cards.
    @State private var draggedFrameID: UUID?
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let canvasExportError {
                Text(canvasExportError)
                    .font(.caption)
                    .foregroundStyle(KobiTheme.statusError)
                    .padding(.horizontal, 10)
            }
            Divider()
            if canvasViewModel.frames.isEmpty {
                emptyState
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        KobiTheme.canvasBase

                        ForEach(canvasViewModel.frames) { frame in
                            CanvasFrameCell(
                                frame: frame,
                                isSharedURLMode: canvasViewModel.isSharedURLMode,
                                onRemove: { canvasViewModel.removeFrame(frame) },
                                isBeingDragged: frame.id == draggedFrameID,
                                onDragChanged: { translation in
                                    handleDragChanged(frameID: frame.id, translation: translation)
                                },
                                onDragEnded: { translation in
                                    handleDragEnded(frameID: frame.id, translation: translation)
                                }
                            )
                            .position(currentPosition(for: frame))
                            .zIndex(frame.id == draggedFrameID ? 1 : 0)
                        }
                    }
                    .frame(width: CanvasViewModel.canvasSize.width, height: CanvasViewModel.canvasSize.height)
                }
            }
        }
        .onChange(of: appState.triggerFocusURLBar) { _, _ in
            guard canvasViewModel.isSharedURLMode else { return }
            isSharedURLFieldFocused = true
        }
    }

    private func currentPosition(for frame: SimulatorViewModel) -> CGPoint {
        let base = canvasViewModel.position(for: frame.id)
        guard frame.id == draggedFrameID else { return base }
        return CGPoint(x: base.x + dragTranslation.width, y: base.y + dragTranslation.height)
    }

    private func handleDragChanged(frameID: UUID, translation: CGSize) {
        draggedFrameID = frameID
        dragTranslation = translation
    }

    private func handleDragEnded(frameID: UUID, translation: CGSize) {
        let base = canvasViewModel.position(for: frameID)
        canvasViewModel.setPosition(
            for: frameID,
            position: CGPoint(x: base.x + translation.width, y: base.y + translation.height)
        )
        draggedFrameID = nil
        dragTranslation = .zero
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Toggle("canvas.toolbar.sharedURL", isOn: $canvasViewModel.isSharedURLMode)
                .toggleStyle(.checkbox)

            if canvasViewModel.isSharedURLMode {
                TextField("simulator.urlBar.placeholder", text: $canvasViewModel.sharedURLString)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSharedURLFieldFocused)
                    .onSubmit { canvasViewModel.broadcastSharedURL() }
                    .accessibilityLabel("accessibility.canvas.sharedURL")
            }

            Divider().frame(height: 20)

            Toggle("canvas.toolbar.scrollSync", isOn: $canvasViewModel.isScrollSyncEnabled)
                .toggleStyle(.checkbox)

            Spacer()

            if showCanvasCopiedAlert {
                Label("canvas.toolbar.copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(KobiTheme.statusOnline)
                    .font(.caption)
            }

            Menu {
                Button("canvas.export.copy") {
                    Task { await exportCombinedSnapshot(action: .copy) }
                }
                Button("canvas.export.save") {
                    Task { await exportCombinedSnapshot(action: .save) }
                }
            } label: {
                Label("canvas.export.button", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(canvasViewModel.frames.isEmpty || isExportingCanvas)
            .accessibilityLabel("accessibility.canvas.exportButton")

            Text(verbatim: "\(canvasViewModel.frames.count)/\(CanvasViewModel.maxFrames)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "accessibility.canvas.framesCount") + ": \(canvasViewModel.frames.count) / \(CanvasViewModel.maxFrames)")
        }
        .padding(10)
    }

    private enum CombinedExportAction {
        case copy
        case save
    }

    private func exportCombinedSnapshot(action: CombinedExportAction) async {
        let frames = canvasViewModel.captureSources()
        guard !frames.isEmpty else { return }

        isExportingCanvas = true
        defer { isExportingCanvas = false }

        do {
            let image = try await CaptureExporter.captureCombinedCanvas(frames: frames, scale: 2)
            switch action {
            case .copy:
                CaptureExporter.copyToClipboard(image)
                withAnimation { showCanvasCopiedAlert = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { showCanvasCopiedAlert = false }
                }
            case .save:
                let data = try CaptureExporter.pngData(from: image)
                _ = await CaptureExporter.save(data, suggestedName: "kobi-canvas-export.png", contentType: .png)
            }
            canvasExportError = nil
        } catch {
            canvasExportError = error.localizedDescription
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("canvas.emptyState.title")
                .font(.headline)
            Text("canvas.emptyState.subtitle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
