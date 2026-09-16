//
//  DeviceDetailPopover.swift
//  Kobi
//

import AppKit
import SwiftUI

struct DeviceDetailPopover: View {
    let device: Device
    let onUseDevice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(device.name)
                .font(.headline)

            specRow(labelKey: "deviceCatalog.detail.viewport", value: "\(device.viewportWidth) × \(device.viewportHeight)")
            specRow(labelKey: "deviceCatalog.detail.dpr", value: formattedDPR)

            if let physicalWidth = device.physicalWidth, let physicalHeight = device.physicalHeight {
                specRow(labelKey: "deviceCatalog.detail.resolution", value: "\(physicalWidth) × \(physicalHeight)")
            }

            if let diagonal = device.diagonalInches {
                specRow(labelKey: "deviceCatalog.detail.diagonal", value: String(format: "%.1f\"", diagonal))
            }

            if !device.userAgent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("deviceCatalog.detail.userAgent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Text(verbatim: device.userAgent)
                            .font(.caption2)
                            .fontDesign(.monospaced)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            copyToClipboard(device.userAgent)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("deviceCatalog.detail.copyUserAgent")
                    }
                }
            }

            Button("deviceCatalog.detail.useDevice", action: onUseDevice)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var formattedDPR: String {
        device.pixelRatio.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(device.pixelRatio))×"
            : String(format: "%.2f×", device.pixelRatio)
    }

    private func specRow(labelKey: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(labelKey)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
