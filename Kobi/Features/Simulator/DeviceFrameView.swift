//
//  DeviceFrameView.swift
//  Kobi
//
//  Hardware Chassis & Viewport Simulation matching docs/UI_SPECIFICATION.md
//

import SwiftUI

enum DeviceOrientation: String, Codable, Sendable {
    case portrait
    case landscape
}

enum DeviceFrameMetrics {
    static let defaultBezelWidth: CGFloat = 11
    static let iphoneOuterRadius: CGFloat = 55
    static let androidOuterRadius: CGFloat = 42

    static func cornerRadius(for device: Device) -> CGFloat {
        switch device.notchStyle {
        case .dynamicIsland, .notch:
            iphoneOuterRadius
        case .punchHoleCenter, .punchHoleCorner:
            androidOuterRadius
        case .none:
            device.category == .tablet ? 24 : 16
        }
    }

    static func bezelWidth(for device: Device) -> CGFloat {
        device.category == .tablet ? 16 : defaultBezelWidth
    }

    static func viewportSize(device: Device, orientation: DeviceOrientation) -> CGSize {
        switch orientation {
        case .portrait:
            CGSize(width: CGFloat(device.viewportWidth), height: CGFloat(device.viewportHeight))
        case .landscape:
            CGSize(width: CGFloat(device.viewportHeight), height: CGFloat(device.viewportWidth))
        }
    }

    static func naturalSize(device: Device, orientation: DeviceOrientation, frameVisible: Bool) -> CGSize {
        let viewport = viewportSize(device: device, orientation: orientation)
        guard frameVisible else { return viewport }
        let bezel = bezelWidth(for: device)
        return CGSize(width: viewport.width + bezel * 2, height: viewport.height + bezel * 2)
    }
}

struct DeviceFrameView<Content: View>: View {
    let device: Device
    let orientation: DeviceOrientation
    let isFrameVisible: Bool
    @ViewBuilder let content: () -> Content

    private var viewportSize: CGSize {
        DeviceFrameMetrics.viewportSize(device: device, orientation: orientation)
    }

    private var bezelWidth: CGFloat {
        DeviceFrameMetrics.bezelWidth(for: device)
    }

    private var outerRadius: CGFloat {
        DeviceFrameMetrics.cornerRadius(for: device)
    }

    private var innerRadius: CGFloat {
        max(outerRadius - bezelWidth, 4)
    }

    private var effectiveNotchStyle: NotchStyle {
        orientation == .landscape ? .none : device.notchStyle
    }

    var body: some View {
        ZStack {
            if isFrameVisible {
                // Physical Hardware Side Buttons
                if orientation == .portrait, device.category == .smartphone {
                    hardwareButtons
                        .accessibilityHidden(true)
                }

                // Titanium / Graphite Outer Chassis
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(KobiTheme.titaniumBlack)
                    .overlay(
                        RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        KobiTheme.titaniumBorder.opacity(0.8),
                                        KobiTheme.titaniumBorder.opacity(0.2),
                                        KobiTheme.titaniumBorder.opacity(0.5),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .frame(
                        width: viewportSize.width + bezelWidth * 2,
                        height: viewportSize.height + bezelWidth * 2
                    )
                    .hardwareBezelShadow()
                    .accessibilityHidden(true)
            }

            // Real WKWebView Viewport
            content()
                .frame(width: viewportSize.width, height: viewportSize.height)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isFrameVisible ? innerRadius : 0,
                        style: .continuous
                    )
                )

            // Hardware Cutout Overlays
            if isFrameVisible {
                notchOverlay
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Hardware Buttons

    @ViewBuilder
    private var hardwareButtons: some View {
        let frameHeight = viewportSize.height + bezelWidth * 2
        let frameWidth = viewportSize.width + bezelWidth * 2

        // Left side buttons: Action button, Volume Up, Volume Down
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(KobiTheme.titaniumBorder)
                .frame(width: 3, height: 26) // Action Button

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(KobiTheme.titaniumBorder)
                .frame(width: 3, height: 48) // Volume Up

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(KobiTheme.titaniumBorder)
                .frame(width: 3, height: 48) // Volume Down
        }
        .offset(x: -(frameWidth / 2) - 1.5, y: -frameHeight * 0.18)

        // Right side: Power / Side Button
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(KobiTheme.titaniumBorder)
            .frame(width: 3, height: 68)
            .offset(x: (frameWidth / 2) + 1.5, y: -frameHeight * 0.12)
    }

    // MARK: - Notch & Dynamic Island Overlays

    @ViewBuilder
    private var notchOverlay: some View {
        switch effectiveNotchStyle {
        case .none:
            EmptyView()

        case .dynamicIsland:
            ZStack {
                Capsule()
                    .fill(KobiTheme.dynamicIsland)
                    .frame(width: 120, height: 35)

                // Sub-pixel camera lens & FaceID sensor glints
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.1, green: 0.12, blue: 0.2))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                    Spacer()
                    Circle()
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                        .frame(width: 10, height: 10)
                }
                .frame(width: 80)
            }
            .offset(y: -(viewportSize.height / 2) + 20)

        case .notch:
            Capsule()
                .fill(Color.black)
                .frame(width: viewportSize.width * 0.38, height: 26)
                .offset(y: -(viewportSize.height / 2) + 13)

        case .punchHoleCenter:
            Circle()
                .fill(Color.black)
                .frame(width: 11, height: 11)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .offset(y: -(viewportSize.height / 2) + 12)

        case .punchHoleCorner:
            Circle()
                .fill(Color.black)
                .frame(width: 11, height: 11)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .offset(x: viewportSize.width / 2 - 24, y: -(viewportSize.height / 2) + 14)
        }
    }
}
