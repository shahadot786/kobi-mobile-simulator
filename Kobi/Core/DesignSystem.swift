//
//  DesignSystem.swift
//  Kobi
//
//  Canonical Design Tokens matching docs/UI_SPECIFICATION.md
//

import SwiftUI

enum KobiTheme {
    // MARK: - Semantic Colors

    static let windowBase = Color(nsColor: .windowBackgroundColor)
    static let canvasBase = Color(nsColor: .underPageBackgroundColor)
    static let surfaceContainer = Color(nsColor: .controlBackgroundColor)
    static let hairlineSeparator = Color(nsColor: .separatorColor)
    static let primaryAccent = Color(nsColor: .controlAccentColor)

    // MARK: - Diagnostics & Telemetry

    // Apple's system colors already shift hue/brightness between Light and Dark appearance
    // (e.g. systemGreen is #34c759 in Light, #30d158 in Dark) — using the NSColor-backed
    // variants instead of fixed hex literals keeps telemetry status colors correct in both.

    static let statusOnline = Color(nsColor: .systemGreen)
    static let statusWarning = Color(nsColor: .systemOrange)
    static let statusError = Color(nsColor: .systemRed)
    static let metricAccent = Color(nsColor: .systemPurple)

    // MARK: - Hardware Chassis Colors

    static let titaniumBlack = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let titaniumBorder = Color(red: 0.22, green: 0.22, blue: 0.24)
    static let dynamicIsland = Color.black

    // MARK: - Radii

    static let controlRadius: CGFloat = 6
    static let cardRadius: CGFloat = 8
    static let popoverRadius: CGFloat = 10
}

// MARK: - Elevation & Shadow Modifiers

struct HardwareBezelShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 16)
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func hardwareBezelShadow() -> some View {
        modifier(HardwareBezelShadow())
    }

    /// Applies tabular monospace numbers to prevent UI jitter during dimension / latency changes
    func telemetryFont(size: CGFloat = 11, weight: Font.Weight = .medium) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
            .monospacedDigit()
    }
}

// MARK: - Dot Grid Background for Simulator Canvas

struct StudioDotGridCanvas: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let dotRadius: CGFloat = 1.25
            let dotColor = Color.primary.opacity(0.06)

            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
