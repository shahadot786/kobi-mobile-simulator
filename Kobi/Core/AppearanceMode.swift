//
//  AppearanceMode.swift
//  Kobi
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .light: "settings.appearance.light"
        case .dark: "settings.appearance.dark"
        case .system: "settings.appearance.system"
        }
    }
}
