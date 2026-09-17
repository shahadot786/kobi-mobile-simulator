//
//  DevToolsPanelView.swift
//  Kobi
//
//  Phase 10 — Debugger & DevTools panel: console/JS-error log and network request log.
//

import SwiftUI

struct DevToolsPanelView: View {
    @Bindable var viewModel: SimulatorViewModel
    let onDismiss: () -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case console
        case network

        var id: String { rawValue }

        var title: String {
            switch self {
            case .console: String(localized: "devTools.tab.console")
            case .network: String(localized: "devTools.tab.network")
            }
        }
    }

    @State private var selectedTab: Tab = .console

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            switch selectedTab {
            case .console: consoleList
            case .network: networkList
            }
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            Text("devTools.title")
                .font(.headline)

            Spacer()

            Button("devTools.action.clear") {
                switch selectedTab {
                case .console: viewModel.clearConsoleLogs()
                case .network: break
                }
            }
            .font(.caption)
            .disabled(selectedTab == .console && viewModel.consoleLogEntries.isEmpty)

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
    }

    private var consoleList: some View {
        Group {
            if viewModel.consoleLogEntries.isEmpty {
                emptyState(labelKey: "devTools.console.empty")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.consoleLogEntries) { entry in
                            consoleRow(entry)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func consoleRow(_ entry: ConsoleLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: consoleIcon(for: entry.level))
                .foregroundStyle(consoleColor(for: entry.level))
                .font(.caption)
                .frame(width: 14)

            Text(verbatim: entry.message)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(consoleColor(for: entry.level))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func consoleIcon(for level: ConsoleLogLevel) -> String {
        switch level {
        case .log: "chevron.right"
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func consoleColor(for level: ConsoleLogLevel) -> Color {
        switch level {
        case .log: .primary
        case .info: KobiTheme.primaryAccent
        case .warn: KobiTheme.statusWarning
        case .error: KobiTheme.statusError
        }
    }

    private var networkList: some View {
        Group {
            if viewModel.networkLogEntries.isEmpty {
                emptyState(labelKey: "devTools.network.empty")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.networkLogEntries) { entry in
                            networkRow(entry)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func networkRow(_ entry: NetworkLogEntry) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: entry.method)
                .font(.caption2.weight(.semibold))
                .frame(width: 44, alignment: .leading)

            Text(verbatim: entry.path)
                .font(.caption)
                .fontDesign(.monospaced)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: entry.statusCode.map(String.init) ?? "—")
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor(for: entry.statusCode))
                .frame(width: 32)

            Text(verbatim: "\(Int(entry.durationMilliseconds)) ms")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            Text(verbatim: formattedByteCount(entry.byteCount))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func statusColor(for statusCode: Int?) -> Color {
        guard let statusCode else { return .secondary }
        switch statusCode {
        case 200 ..< 400: KobiTheme.statusOnline
        case 400 ..< 500: KobiTheme.statusWarning
        default: KobiTheme.statusError
        }
    }

    private func formattedByteCount(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private func emptyState(labelKey: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text(labelKey)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
