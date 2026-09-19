//
//  CompareDevicesView.swift
//  Kobi
//
//  Phase 16 — picks two open canvas frames, captures a snapshot of each, then hands off to
//  `DiffView` for the before/after reveal slider.
//

import SwiftUI

struct CompareDevicesView: View {
    let frames: [SimulatorViewModel]
    let onDismiss: () -> Void

    @State private var leftFrameID: UUID?
    @State private var rightFrameID: UUID?
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var diffPair: DiffPair?

    private struct DiffPair {
        let left: NSImage
        let right: NSImage
        let leftLabel: String
        let rightLabel: String
    }

    var body: some View {
        if let diffPair {
            DiffView(
                leftImage: diffPair.left,
                rightImage: diffPair.right,
                leftLabel: diffPair.leftLabel,
                rightLabel: diffPair.rightLabel,
                onDismiss: onDismiss
            )
        } else {
            pickerBody
        }
    }

    private var pickerBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("diffView.pickerTitle")
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
            }

            Picker("diffView.deviceA", selection: $leftFrameID) {
                Text("diffView.selectDevice").tag(UUID?.none)
                ForEach(frames) { frame in
                    Text(frame.device.name).tag(Optional(frame.id))
                }
            }

            Picker("diffView.deviceB", selection: $rightFrameID) {
                Text("diffView.selectDevice").tag(UUID?.none)
                ForEach(frames) { frame in
                    Text(frame.device.name).tag(Optional(frame.id))
                }
            }

            if let captureError {
                Text(captureError)
                    .font(.caption)
                    .foregroundStyle(KobiTheme.statusError)
            }

            HStack {
                Spacer()
                if isCapturing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("diffView.compare") {
                    Task { await capture() }
                }
                .buttonStyle(.borderedProminent)
                .tint(KobiTheme.primaryAccent)
                .disabled(leftFrameID == nil || rightFrameID == nil || leftFrameID == rightFrameID || isCapturing)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func capture() async {
        guard let leftID = leftFrameID, let rightID = rightFrameID,
              let leftFrame = frames.first(where: { $0.id == leftID }),
              let rightFrame = frames.first(where: { $0.id == rightID }),
              let leftWebView = leftFrame.webView, let rightWebView = rightFrame.webView
        else {
            return
        }

        isCapturing = true
        captureError = nil
        defer { isCapturing = false }

        do {
            let leftImage = try await CaptureExporter.captureSnapshot(
                webView: leftWebView,
                options: CaptureDeviceOptions(
                    device: leftFrame.device,
                    orientation: leftFrame.orientation,
                    includeFrame: true,
                    transparentBackground: true,
                    scale: 1.0
                )
            )
            let rightImage = try await CaptureExporter.captureSnapshot(
                webView: rightWebView,
                options: CaptureDeviceOptions(
                    device: rightFrame.device,
                    orientation: rightFrame.orientation,
                    includeFrame: true,
                    transparentBackground: true,
                    scale: 1.0
                )
            )
            diffPair = DiffPair(
                left: leftImage,
                right: rightImage,
                leftLabel: leftFrame.device.name,
                rightLabel: rightFrame.device.name
            )
        } catch {
            captureError = error.localizedDescription
        }
    }
}
