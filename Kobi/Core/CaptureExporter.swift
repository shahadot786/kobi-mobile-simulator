//
//  CaptureExporter.swift
//  Kobi
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum CaptureExportError: LocalizedError {
    case snapshotFailed
    case renderFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .snapshotFailed: String(localized: "export.error.snapshotFailed")
        case .renderFailed: String(localized: "export.error.renderFailed")
        case .pngEncodingFailed: String(localized: "export.error.pngEncodingFailed")
        }
    }
}

/// Groups the device-chrome rendering parameters shared by `captureSnapshot`, `captureBlankMockup`,
/// and the private `render` helper — keeps each call site under this project's parameter-count limit.
struct CaptureDeviceOptions {
    let device: Device
    let orientation: DeviceOrientation
    let includeFrame: Bool
    let transparentBackground: Bool
    let scale: CGFloat
}

/// A single frame contributed to a combined multi-device snapshot.
struct CaptureFrame {
    let device: Device
    let orientation: DeviceOrientation
    let webView: WKWebView
}

/// Captures live `WKWebView` content and/or device chrome into export-ready PNGs.
///
/// The `WKWebView` snapshot is taken at the window's native backing scale; the requested
/// `scale` (1x/2x/3x) is applied afterward by `ImageRenderer`, independent of the device's own
/// simulated DPR — this mirrors how asset-catalog `@1x/@2x/@3x` export works elsewhere on macOS.
@MainActor
enum CaptureExporter {
    static func captureSnapshot(webView: WKWebView, options: CaptureDeviceOptions) async throws -> NSImage {
        let contentImage = try await snapshot(of: webView)
        return try render(options: options) {
            Image(nsImage: contentImage)
        }
    }

    static func captureBlankMockup(
        device: Device,
        orientation: DeviceOrientation,
        includeFrame: Bool,
        transparentBackground: Bool,
        scale: CGFloat
    ) throws -> NSImage {
        try render(
            options: CaptureDeviceOptions(
                device: device,
                orientation: orientation,
                includeFrame: includeFrame,
                transparentBackground: transparentBackground,
                scale: scale
            )
        ) {
            Color.clear
        }
    }

    static func captureCombinedCanvas(frames: [CaptureFrame], scale: CGFloat) async throws -> NSImage {
        var composites: [NSImage] = []
        for frame in frames {
            let contentImage = try await snapshot(of: frame.webView)
            let composite = try render(
                options: CaptureDeviceOptions(
                    device: frame.device,
                    orientation: frame.orientation,
                    includeFrame: true,
                    transparentBackground: true,
                    scale: scale
                )
            ) {
                Image(nsImage: contentImage)
            }
            composites.append(composite)
        }
        return try renderRow(images: composites, scale: scale)
    }

    // MARK: - Clipboard / Disk

    static func copyToClipboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    static func copyFileToClipboard(at url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    static func pngData(from image: NSImage) throws -> Data {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureExportError.pngEncodingFailed
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = image.size
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureExportError.pngEncodingFailed
        }
        return data
    }

    static func save(_ data: Data, suggestedName: String, contentType: UTType) async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        let response = await panel.beginSheetModal()
        guard response == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    static func save(fileAt sourceURL: URL, suggestedName: String, contentType: UTType) async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        let response = await panel.beginSheetModal()
        guard response == .OK, let destinationURL = panel.url else { return false }
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    /// Prompts once for a destination folder, for batch exports that then write many files into
    /// it directly — as opposed to `save(_:suggestedName:contentType:)`, which prompts per file.
    static func chooseFolder(prompt: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        let response = await panel.beginSheetModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    static func write(_ data: Data, toFileNamed fileName: String, in folder: URL) throws {
        try data.write(to: folder.appendingPathComponent(fileName))
    }

    // MARK: - Private

    private static func snapshot(of webView: WKWebView) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            webView.takeSnapshot(with: config) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CaptureExportError.snapshotFailed)
                }
            }
        }
    }

    private static func render(
        options: CaptureDeviceOptions,
        @ViewBuilder content: @escaping () -> some View
    ) throws -> NSImage {
        // Hardware side buttons are drawn via `.offset` past the chassis's own frame, so
        // `ImageRenderer`'s ideal-size sizing (no `proposedSize` set) would otherwise clip them.
        let composite = DeviceFrameView(
            device: options.device,
            orientation: options.orientation,
            isFrameVisible: options.includeFrame
        ) {
            content()
        }
        .padding(.horizontal, options.includeFrame ? 8 : 0)
        let renderer = ImageRenderer(content: composite)
        renderer.scale = options.scale
        renderer.isOpaque = !options.transparentBackground
        guard let nsImage = renderer.nsImage else {
            throw CaptureExportError.renderFailed
        }
        return nsImage
    }

    private static func renderRow(images: [NSImage], scale: CGFloat) throws -> NSImage {
        let row = HStack(alignment: .top, spacing: 24) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
            }
        }
        .padding(24)
        .background(KobiTheme.canvasBase)

        let renderer = ImageRenderer(content: row)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let nsImage = renderer.nsImage else {
            throw CaptureExportError.renderFailed
        }
        return nsImage
    }
}

/// `NSOpenPanel` is a subclass of `NSSavePanel`, so this single extension covers both.
private extension NSSavePanel {
    @MainActor
    func beginSheetModal() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            self.begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}
