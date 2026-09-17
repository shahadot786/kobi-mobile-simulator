//
//  MockupLibraryView.swift
//  Kobi
//
//  Phase 4b — standalone blank-mockup browser. Reuses the same device-catalog sidebar as
//  Single/Canvas mode (selection toggles which devices appear here) per docs/DESIGN_BRIEF.md
//  §3.3b: "same catalog UI as #5, toggled into blank mockup mode."
//  Phase 7 — Polish, accessibility, and localization QA
//

import SwiftUI
import UniformTypeIdentifiers

struct MockupLibraryView: View {
    let devices: [Device]
    let onRemove: (Device) -> Void
    let onSelectAllFiltered: () -> Void
    let onClearSelection: () -> Void

    @State private var resolutionScale: ResolutionScale = .x2
    @State private var isBatchExporting = false
    @State private var batchExportError: String?
    @State private var batchExportProgress: (completed: Int, total: Int)?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let batchExportError {
                Text(batchExportError)
                    .font(.caption)
                    .foregroundStyle(KobiTheme.statusError)
                    .padding(.horizontal, 10)
            }
            Divider()
            if devices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20)], spacing: 20) {
                        ForEach(devices) { device in
                            MockupGridCell(
                                device: device,
                                resolutionScale: resolutionScale,
                                onRemove: { onRemove(device) }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("mockup.selectedCount \(devices.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "mockup.selectedCount \(devices.count)"))

            Button("mockup.selectAllFiltered", action: onSelectAllFiltered)
                .font(.caption)

            Button("mockup.clear", action: onClearSelection)
                .font(.caption)
                .disabled(devices.isEmpty)

            Divider().frame(height: 16)

            Text("mockup.resolutionLabel")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("mockup.resolutionLabel", selection: $resolutionScale) {
                ForEach(ResolutionScale.allCases) { scale in
                    Text(scale.label).tag(scale)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            .accessibilityLabel("mockup.resolutionLabel")

            Spacer()

            if let batchExportProgress {
                Text("mockup.exportingProgress \(batchExportProgress.completed) \(batchExportProgress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await batchExportAll() }
            } label: {
                Label("mockup.downloadAll", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(KobiTheme.primaryAccent)
            .disabled(devices.isEmpty || isBatchExporting)
            .accessibilityLabel("mockup.downloadAll")
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("mockup.empty.title")
                .font(.headline)
            Text("mockup.empty.subtitle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func batchExportAll() async {
        guard let folder = await CaptureExporter
            .chooseFolder(prompt: String(localized: "mockup.batchExport.choosePrompt")) else { return }

        isBatchExporting = true
        batchExportProgress = (0, devices.count)
        batchExportError = nil
        defer {
            isBatchExporting = false
            batchExportProgress = nil
        }

        var failedDeviceNames: [String] = []

        for (index, device) in devices.enumerated() {
            do {
                let image = try CaptureExporter.captureBlankMockup(
                    device: device,
                    orientation: .portrait,
                    includeFrame: true,
                    transparentBackground: true,
                    scale: CGFloat(resolutionScale.rawValue)
                )
                let data = try CaptureExporter.pngData(from: image)
                try CaptureExporter.write(data, toFileNamed: "\(device.id)-mockup.png", in: folder)
            } catch {
                failedDeviceNames.append(device.name)
            }
            batchExportProgress = (index + 1, devices.count)
            // Every step here is synchronous, so without a suspension point the run loop never
            // gets a chance to redraw the progress label between devices.
            await Task.yield()
        }

        if !failedDeviceNames.isEmpty {
            batchExportError =
                String(localized: "mockup.batchExport.failed \(failedDeviceNames.joined(separator: ", "))")
        }
    }
}

private struct MockupGridCell: View {
    let device: Device
    let resolutionScale: ResolutionScale
    let onRemove: () -> Void

    @State private var previewImage: NSImage?
    @State private var errorMessage: String?
    @State private var showCopiedAlert = false
    @State private var isBusy = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(device.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("mockup.cell.removeHelp")
                .accessibilityLabel("mockup.cell.removeHelp")
            }

            ZStack {
                CheckeredBackground()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                        .padding(8)
                } else {
                    ProgressView()
                }
            }

            Text(verbatim: "\(device.viewportWidth) × \(device.viewportHeight) px")
                .telemetryFont(size: 10)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(KobiTheme.statusError)
            }

            HStack(spacing: 8) {
                if showCopiedAlert {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KobiTheme.statusOnline)
                        .font(.caption)
                }

                Spacer()

                Button("mockup.cell.copy") { Task { await copyImage() } }
                Button("mockup.cell.save") { Task { await saveImage() } }
            }
            .font(.caption)
            .disabled(isBusy)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: device.id) {
            await generatePreview()
        }
    }

    private func generatePreview() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let image = try CaptureExporter.captureBlankMockup(
                device: device,
                orientation: .portrait,
                includeFrame: true,
                transparentBackground: true,
                scale: 1.0
            )
            previewImage = image
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyImage() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let image = try CaptureExporter.captureBlankMockup(
                device: device,
                orientation: .portrait,
                includeFrame: true,
                transparentBackground: true,
                scale: CGFloat(resolutionScale.rawValue)
            )
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
            let image = try CaptureExporter.captureBlankMockup(
                device: device,
                orientation: .portrait,
                includeFrame: true,
                transparentBackground: true,
                scale: CGFloat(resolutionScale.rawValue)
            )
            let data = try CaptureExporter.pngData(from: image)
            _ = await CaptureExporter.save(
                data,
                suggestedName: "\(device.id)-mockup.png",
                contentType: .png
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CheckeredBackground: View {
    private let tileSize: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            let lightSquare = Color(nsColor: .controlBackgroundColor)
            let darkSquare = Color.primary.opacity(0.06)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(lightSquare))

            for row in stride(from: 0, to: size.height, by: tileSize) {
                for column in stride(from: 0, to: size.width, by: tileSize) {
                    let columnIndex = Int(column / tileSize)
                    let rowIndex = Int(row / tileSize)

                    guard (columnIndex + rowIndex).isMultiple(of: 2) else { continue }

                    context.fill(
                        Path(CGRect(x: column, y: row, width: tileSize, height: tileSize)),
                        with: .color(darkSquare)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
