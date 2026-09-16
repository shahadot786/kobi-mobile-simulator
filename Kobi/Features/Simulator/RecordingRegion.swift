//
//  RecordingRegion.swift
//  Kobi
//

import AppKit
import SwiftUI

/// Tracks the on-screen rect (in the hosting `NSWindow`'s coordinate space) of the device
/// frame currently being displayed, so `ScreenRecorder` can crop `ScreenCaptureKit` capture to
/// just that region instead of the whole window.
@MainActor
final class RecordingRegion {
    weak var window: NSWindow?
    var frameInWindow: CGRect = .zero
}

/// Invisible `NSView` overlay that reports its own frame (converted to window coordinates)
/// into a `RecordingRegion` on every layout pass — SwiftUI has no public API to read a view's
/// on-screen rect directly, so this is the standard AppKit-bridging escape hatch for it.
struct FrameRegionReader: NSViewRepresentable {
    let region: RecordingRegion

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.region = region
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.region = region
        nsView.reportRegion()
    }

    final class TrackingView: NSView {
        var region: RecordingRegion?

        override func layout() {
            super.layout()
            reportRegion()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportRegion()
        }

        func reportRegion() {
            guard let window else { return }
            region?.window = window
            region?.frameInWindow = convert(bounds, to: nil)
        }
    }
}
