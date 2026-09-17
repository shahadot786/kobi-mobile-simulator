//
//  Device.swift
//  Kobi
//

import Foundation
import SwiftUI

enum DeviceCategory: String, Codable, CaseIterable {
    case smartphone
    case tablet
    case wearable
    case desktop
    case foldable

    var titleKey: LocalizedStringKey {
        switch self {
        case .smartphone: "deviceCatalog.category.smartphone"
        case .tablet: "deviceCatalog.category.tablet"
        case .wearable: "deviceCatalog.category.wearable"
        case .desktop: "deviceCatalog.category.desktop"
        case .foldable: "deviceCatalog.category.foldable"
        }
    }
}

enum NotchStyle: String, Codable {
    case none
    case notch
    case dynamicIsland
    case punchHoleCenter
    case punchHoleCorner
}

enum BrowserEngine: String, Codable, Hashable {
    case webkit
    case blink
    case gecko
}

enum ColorGamut: String, Codable, Hashable {
    case srgb
    case p3
    case rec2020
}

/// One orientation's `env(safe-area-inset-*)` equivalent, in CSS points matching
/// `viewportWidth`/`viewportHeight` — not physical pixels.
struct SafeAreaEdgeInsets: Codable, Hashable {
    var top: Double
    var bottom: Double
    var leading: Double
    var trailing: Double
}

/// Safe-area insets genuinely vary by orientation (a notch/Dynamic Island cutout moves from
/// top to a side edge when rotated), so this is captured per-orientation rather than as a
/// single fixed inset.
struct DeviceSafeAreaInsets: Codable, Hashable {
    var portrait: SafeAreaEdgeInsets
    var landscape: SafeAreaEdgeInsets
}

struct Device: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let brand: String
    let category: DeviceCategory
    let viewportWidth: Int
    let viewportHeight: Int
    let pixelRatio: Double
    let notchStyle: NotchStyle
    let userAgent: String
    var diagonalInches: Double?
    var physicalWidth: Int?
    var physicalHeight: Int?
    var releaseYear: Int?

    // Phase 9 additions — all optional so previously-persisted custom devices (encoded before
    // these fields existed) keep decoding via Codable's default `decodeIfPresent` behavior for
    // Optional properties, no manual migration needed.
    var ppi: Double?
    var safeAreaInsets: DeviceSafeAreaInsets?
    var refreshRateHz: Int?
    var osVersion: String?
    var browserEngine: BrowserEngine?
    var colorGamut: ColorGamut?
    var supportsHDR: Bool?
}
