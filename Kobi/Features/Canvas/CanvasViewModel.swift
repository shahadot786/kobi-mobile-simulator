//
//  CanvasViewModel.swift
//  Kobi
//

import Foundation
import Observation
import WebKit

@Observable
final class CanvasViewModel {
    static let maxFrames = 6
    static let cardSize = CGSize(width: 280, height: 500)
    static let canvasSize = CGSize(width: 2400, height: 1600)

    private(set) var frames: [SimulatorViewModel] = []
    private(set) var framePositions: [UUID: CGPoint] = [:]
    var sharedURLString: String = "http://localhost:3000"
    var isSharedURLMode: Bool = true
    var isScrollSyncEnabled: Bool = false

    private static let gap: CGFloat = 24
    private static let canvasPadding: CGFloat = 40

    var canAddFrame: Bool {
        frames.count < Self.maxFrames
    }

    func isOpen(_ device: Device) -> Bool {
        frames.contains { $0.device.id == device.id }
    }

    /// Tapping a device in canvas mode toggles it: add if not already open (up to the
    /// concurrency cap), remove if it is — mirrors the sidebar's multi-select highlighting.
    func toggleFrame(for device: Device) {
        if let existing = frames.first(where: { $0.device.id == device.id }) {
            removeFrame(existing)
            return
        }
        guard canAddFrame else { return }
        let frame = SimulatorViewModel(device: device, initialURLString: sharedURLString)
        frame.onScrollFraction = { [weak self, weak frame] fractionX, fractionY in
            guard let self, let frame else { return }
            relayScroll(from: frame, fractionX: fractionX, fractionY: fractionY)
        }
        framePositions[frame.id] = cascadePosition(forIndex: frames.count)
        frames.append(frame)
    }

    func addFrame(
        for device: Device,
        urlString: String,
        orientation: DeviceOrientation = .portrait,
        position: CGPoint? = nil
    ) {
        guard canAddFrame else { return }
        let frame = SimulatorViewModel(device: device, initialURLString: urlString)
        frame.orientation = orientation
        frame.onScrollFraction = { [weak self, weak frame] fractionX, fractionY in
            guard let self, let frame else { return }
            relayScroll(from: frame, fractionX: fractionX, fractionY: fractionY)
        }
        framePositions[frame.id] = position ?? cascadePosition(forIndex: frames.count)
        frames.append(frame)
    }

    func clearAllFrames() {
        frames.removeAll()
        framePositions.removeAll()
    }

    func removeFrame(_ frame: SimulatorViewModel) {
        frames.removeAll { $0.id == frame.id }
        framePositions.removeValue(forKey: frame.id)
    }

    func broadcastSharedURL() {
        for frame in frames {
            frame.load(urlString: sharedURLString)
        }
    }

    /// The center point (matching SwiftUI's `.position()`) a frame's card is placed at on the
    /// free-form canvas. Falls back to a cascaded default if the frame has no recorded position
    /// yet (shouldn't normally happen — `toggleFrame` always assigns one on add).
    func position(for frameID: UUID) -> CGPoint {
        framePositions[frameID] ?? cascadePosition(forIndex: frames.count)
    }

    /// Free placement — the dragged card moves to wherever the user drops it, with no swapping
    /// or snapping against other cards.
    func setPosition(for frameID: UUID, position: CGPoint) {
        let halfWidth = Self.cardSize.width / 2
        let halfHeight = Self.cardSize.height / 2
        framePositions[frameID] = CGPoint(
            x: min(max(position.x, halfWidth), Self.canvasSize.width - halfWidth),
            y: min(max(position.y, halfHeight), Self.canvasSize.height - halfHeight)
        )
    }

    private func cascadePosition(forIndex index: Int) -> CGPoint {
        let columns = max(Int((Self.canvasSize.width - Self.canvasPadding * 2) / (Self.cardSize.width + Self.gap)), 1)
        let column = index % columns
        let row = index / columns
        return CGPoint(
            x: Self.canvasPadding + CGFloat(column) * (Self.cardSize.width + Self.gap) + Self.cardSize.width / 2,
            y: Self.canvasPadding + CGFloat(row) * (Self.cardSize.height + Self.gap) + Self.cardSize.height / 2
        )
    }

    /// Only frames whose `WKWebView` has actually attached (weak ref set once `makeNSView` runs)
    /// are included — a frame added this instant and not yet laid out has no content to shoot.
    func captureSources() -> [(device: Device, orientation: DeviceOrientation, webView: WKWebView)] {
        frames.compactMap { frame in
            guard let webView = frame.webView else { return nil }
            return (frame.device, frame.orientation, webView)
        }
    }

    private func relayScroll(from source: SimulatorViewModel, fractionX: Double, fractionY: Double) {
        guard isScrollSyncEnabled else { return }
        for frame in frames where frame.id != source.id {
            frame.scrollTo(fractionX: fractionX, fractionY: fractionY)
        }
    }
}
