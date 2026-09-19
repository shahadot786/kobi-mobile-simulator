//
//  SettingsView.swift
//  Kobi
//
//  Phase 6 — Tabbed Settings with General, Shortcuts reference panel, and About.
//  Phase 7 — Localization QA & accessibility
//

import SwiftUI

enum SettingsTab: Hashable {
    case general
    case shortcuts
    case about
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("settings.tab.general", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            shortcutsTab
                .tabItem {
                    Label("settings.tab.shortcuts", systemImage: "command")
                }
                .tag(SettingsTab.shortcuts)

            aboutTab
                .tabItem {
                    Label("settings.tab.about", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 480, height: 380)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        @Bindable var appState = appState

        return Form {
            Section {
                Picker("settings.appearance.title", selection: $appState.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("settings.section.appearance")
            }

            Section {
                Text("settings.engine.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.section.rendering")
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        List {
            Section("settings.shortcuts.navigation") {
                shortcutRow(titleKey: "settings.shortcuts.focusURL", keys: ["⌘", "L"])
                shortcutRow(titleKey: "settings.shortcuts.reload", keys: ["⌘", "R"])
                shortcutRow(titleKey: "settings.shortcuts.singleMode", keys: ["⌘", "1"])
                shortcutRow(titleKey: "settings.shortcuts.canvasMode", keys: ["⌘", "2"])
                shortcutRow(titleKey: "settings.shortcuts.mockupsMode", keys: ["⌘", "3"])
                shortcutRow(titleKey: "settings.shortcuts.favoriteSlots", keys: ["⌘", "⌥", "1-9"])
            }

            Section("settings.shortcuts.viewport") {
                shortcutRow(titleKey: "settings.shortcuts.rotate", keys: ["⌘", "⇧", "O"])
                shortcutRow(titleKey: "settings.shortcuts.toggleFrame", keys: ["⌘", "⇧", "F"])
                shortcutRow(titleKey: "settings.shortcuts.zoomFit", keys: ["⌘", "0"])
                shortcutRow(titleKey: "settings.shortcuts.exitKiosk", keys: ["Esc"])
            }

            Section("settings.shortcuts.captureWorkspaces") {
                shortcutRow(titleKey: "settings.shortcuts.workspaces", keys: ["⌘", "⇧", "W"])
                shortcutRow(titleKey: "settings.shortcuts.export", keys: ["⌘", "⇧", "E"])
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func shortcutRow(titleKey: LocalizedStringKey, keys: [String]) -> some View {
        HStack {
            Text(titleKey)
                .font(.system(size: 12))
            Spacer()
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    KeycapView(key: key)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "display.2")
                .font(.system(size: 40))
                .foregroundStyle(KobiTheme.primaryAccent)
                .padding(.top, 24)

            Text("app.displayName")
                .font(.headline)

            Text("settings.about.version")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("settings.about.description")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Spacer()

            Text("settings.about.engineFooter")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
    }
}

// MARK: - Keycap Badge Component

struct KeycapView: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
    }
}
