//
//  DeviceRowView.swift
//  Kobi
//
//  Phase 7 — VoiceOver accessibility and semantic focus
//

import SwiftUI

struct DeviceRowView: View {
    let device: Device
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onShowDetail: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(verbatim: "\(device.brand) · \(device.viewportWidth)×\(device.viewportHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(device.name), \(device.brand), \(device.viewportWidth) × \(device.viewportHeight)")
            .accessibilityHint("accessibility.device.selectHint")

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("deviceCatalog.detail.title")
            .accessibilityLabel("\(String(localized: "accessibility.device.details")): \(device.name)")

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFavorite ? .yellow : .secondary)
            .help("deviceCatalog.action.toggleFavorite")
            .accessibilityLabel(isFavorite ? String(localized: "accessibility.device.unfavorite") :
                String(localized: "accessibility.device.favorite"))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}
