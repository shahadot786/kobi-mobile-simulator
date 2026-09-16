//
//  MediaQueryCheatSheetView.swift
//  Kobi
//
//  Phase 5 — a quick-reference panel of common responsive breakpoints, each copyable as a
//  ready-to-paste `@media` rule, plus the currently active device's own breakpoint.
//  Phase 7 — Polish, localization, and accessibility
//

import SwiftUI

private struct Breakpoint: Identifiable {
    let labelKey: LocalizedStringKey
    let width: Int

    var id: Int { width }
}

private let commonBreakpoints: [Breakpoint] = [
    Breakpoint(labelKey: "mediaQuery.bp.smallPhone", width: 320),
    Breakpoint(labelKey: "mediaQuery.bp.standardPhone", width: 375),
    Breakpoint(labelKey: "mediaQuery.bp.largePhone", width: 428),
    Breakpoint(labelKey: "mediaQuery.bp.smallTablet", width: 768),
    Breakpoint(labelKey: "mediaQuery.bp.largeTablet", width: 1024),
    Breakpoint(labelKey: "mediaQuery.bp.laptop", width: 1280),
    Breakpoint(labelKey: "mediaQuery.bp.desktop", width: 1440),
    Breakpoint(labelKey: "mediaQuery.bp.largeDesktop", width: 1920)
]

struct MediaQueryCheatSheetView: View {
    let currentDeviceName: String
    let currentDeviceWidth: Int
    let onDismiss: () -> Void

    @State private var copiedWidth: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("mediaQuery.sheet.title")
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
                .help("export.dismissHelp")
                .accessibilityLabel("export.dismissHelp")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            List {
                Section("mediaQuery.sheet.currentDevice") {
                    customRow(label: currentDeviceName, width: currentDeviceWidth)
                }
                Section("mediaQuery.sheet.commonBreakpoints") {
                    ForEach(commonBreakpoints) { breakpoint in
                        localizedRow(labelKey: breakpoint.labelKey, width: breakpoint.width)
                    }
                }
            }
        }
        .frame(width: 360, height: 420)
    }

    private func customRow(label: String, width: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                Text(verbatim: "\(width)px")
                    .telemetryFont(size: 11)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            copyButton(for: width)
        }
        .padding(.vertical, 2)
    }

    private func localizedRow(labelKey: LocalizedStringKey, width: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(labelKey)
                    .font(.callout)
                Text(verbatim: "\(width)px")
                    .telemetryFont(size: 11)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            copyButton(for: width)
        }
        .padding(.vertical, 2)
    }

    private func copyButton(for width: Int) -> some View {
        Button {
            copyBreakpoint(width: width)
        } label: {
            if copiedWidth == width {
                Label("mediaQuery.sheet.copied", systemImage: "checkmark")
            } else {
                Label("mediaQuery.sheet.copy", systemImage: "doc.on.doc")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .accessibilityLabel(copiedWidth == width ? String(localized: "mediaQuery.sheet.copied") : String(localized: "mediaQuery.sheet.copy"))
    }

    private func copyBreakpoint(width: Int) {
        let css = "@media (max-width: \(width)px) {\n\n}"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(css, forType: .string)
        withAnimation { copiedWidth = width }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copiedWidth = nil }
        }
    }
}
