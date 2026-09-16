//
//  AppState.swift
//  Kobi
//

import Foundation
import Observation

@Observable
final class AppState {
    var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingCompletedKey) }
    }

    var isOnboardingPresented: Bool = false

    let workspaceStore = WorkspaceStore()
    var isWorkspacesSheetPresented: Bool = false
    var pendingWorkspaceID: UUID?

    // Action triggers dispatched by menu commands or global shortcuts
    var triggerRotateOrientation: UUID?
    var triggerToggleFrame: UUID?
    var triggerReload: UUID?
    var triggerZoomFit: UUID?
    var triggerFocusURLBar: UUID?
    var triggerExportSheet: UUID?

    private static let appearanceModeKey = "appearanceMode"
    private static let onboardingCompletedKey = "hasCompletedOnboarding"

    init() {
        let storedRawValue = UserDefaults.standard.string(forKey: Self.appearanceModeKey)
        appearanceMode = storedRawValue.flatMap(AppearanceMode.init(rawValue:)) ?? .system
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
    }

    func toggleAppearance() {
        switch appearanceMode {
        case .system: appearanceMode = .dark
        case .dark: appearanceMode = .light
        case .light: appearanceMode = .system
        }
    }
}
