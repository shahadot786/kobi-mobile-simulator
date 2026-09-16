//
//  CanvasFrameCell.swift
//  Kobi
//

import SwiftUI

struct CanvasFrameCell: View {
    @Bindable var frame: SimulatorViewModel
    let isSharedURLMode: Bool
    let onRemove: () -> Void
    let isBeingDragged: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    private let cellHeight: CGFloat = 420
    private let keyboardMoveStep: CGFloat = 20

    var body: some View {
        VStack(spacing: 6) {
            header

            if !isSharedURLMode {
                TextField("simulator.urlBar.placeholder", text: $frame.urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { frame.submitURL() }
            }

            ZStack {
                DeviceFrameView(
                    device: frame.device,
                    orientation: frame.orientation,
                    isFrameVisible: frame.isFrameVisible
                ) {
                    WebViewRepresentable(viewModel: frame)
                }
                .scaleEffect(scale)
                .frame(width: naturalSize.width * scale, height: naturalSize.height * scale)

                if let error = frame.loadError {
                    errorOverlay(message: error)
                }
            }
            .frame(height: cellHeight)
        }
        .padding(10)
        .frame(width: CanvasViewModel.cardSize.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(isBeingDragged ? 0.35 : 0), radius: 16, y: 8)
        .scaleEffect(isBeingDragged ? 1.03 : 1)
        .opacity(isBeingDragged ? 0.9 : 1)
        .animation(.interactiveSpring(), value: isBeingDragged)
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

            Spacer()

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

    private func errorOverlay(message: String) -> some View {
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
