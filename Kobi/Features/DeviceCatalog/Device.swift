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
}
