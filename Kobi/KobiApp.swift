//
//  KobiApp.swift
//  Kobi
//
//  Phase 6 & 7 — App commands, menu bar extra, global shortcuts, and onboarding guide.
//

import SwiftUI

@main
struct KobiApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.appearanceMode.colorScheme)
        }
        .defaultSize(width: 960, height: 760)
        .commands {
            CommandMenu("menu.device.title") {
                Button("commands.device.focusURL") {
                    appState.triggerFocusURLBar = UUID()
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("commands.device.rotate") {
                    appState.triggerRotateOrientation = UUID()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("commands.device.toggleFrame") {
                    appState.triggerToggleFrame = UUID()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("commands.device.zoomFit") {
                    appState.triggerZoomFit = UUID()
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("commands.device.reload") {
                    appState.triggerReload = UUID()
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("menu.workspaces.title") {
                Button("commands.workspaces.manage") {
                    appState.isWorkspacesSheetPresented = true
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("commands.capture.export") {
                    appState.triggerExportSheet = UUID()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                ForEach(appState.workspaceStore.workspaces) { ws in
                    Button(ws.name) {
                        appState.pendingWorkspaceID = ws.id
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button("menu.help.welcomeGuide") {
                    appState.isOnboardingPresented = true
                }

                Divider()

                Button("commands.appearance.toggle") {
                    appState.toggleAppearance()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .preferredColorScheme(appState.appearanceMode.colorScheme)
        }

        MenuBarExtra("Kobi", systemImage: "display.2") {
            Text("app.displayName")
                .font(.headline)

            Divider()

            Menu("menuBar.workspaces") {
                ForEach(appState.workspaceStore.workspaces) { ws in
                    Button(ws.name) {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "main")
                        appState.pendingWorkspaceID = ws.id
                    }
                }
            }

            Menu("menuBar.appearance") {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appState.appearanceMode = mode
                    } label: {
                        if mode == appState.appearanceMode {
                            Label(mode.titleKey, systemImage: "checkmark")
                        } else {
                            Text(mode.titleKey)
                        }
                    }
                }
            }

            Divider()

            Button("menuBar.openApp") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("menuBar.quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
