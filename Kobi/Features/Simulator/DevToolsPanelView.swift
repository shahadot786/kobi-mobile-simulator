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
        case performance
        case inspector

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .console: String(localized: "devTools.tab.console")
            case .network: String(localized: "devTools.tab.network")
            case .performance: String(localized: "devTools.tab.performance")
            case .inspector: String(localized: "devTools.tab.inspector")
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
            case .performance: performanceView
            case .inspector: inspectorView
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

            if selectedTab == .performance {
                Button("devTools.action.refresh") {
                    viewModel.refreshPerfMetrics()
                }
                .font(.caption)
            }

            if selectedTab == .console {
                Button("devTools.action.clear") {
                    viewModel.clearConsoleLogs()
                }
                .font(.caption)
                .disabled(viewModel.consoleLogEntries.isEmpty)
            }

            if selectedTab == .network {
                Button("devTools.action.clear") {
                    viewModel.clearNetworkLogs()
                }
                .font(.caption)
                .disabled(viewModel.networkLogEntries.isEmpty)
            }

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

    @ViewBuilder
    private var consoleList: some View {
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

    @ViewBuilder
    private var networkList: some View {
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
        case 200 ..< 400: return KobiTheme.statusOnline
        case 400 ..< 500: return KobiTheme.statusWarning
        default: return KobiTheme.statusError
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

    // MARK: - Performance (Phase 16)

    @ViewBuilder
    private var performanceView: some View {
        if let metrics = viewModel.perfMetrics {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    perfMetricsSection(
                        titleKey: "devTools.performance.timing",
                        rows: [
                            PerfMetricRow(
                                titleKey: "devTools.performance.ttfb",
                                value: formattedMilliseconds(metrics.timeToFirstByteMilliseconds)
                            ),
                            PerfMetricRow(
                                titleKey: "devTools.performance.domContentLoaded",
                                value: formattedMilliseconds(metrics.domContentLoadedMilliseconds)
                            ),
                            PerfMetricRow(
                                titleKey: "devTools.performance.load",
                                value: formattedMilliseconds(metrics.loadMilliseconds)
                            ),
                            PerfMetricRow(
                                titleKey: "devTools.performance.lcp",
                                value: formattedMilliseconds(metrics.largestContentfulPaintMilliseconds)
                            ),
                            PerfMetricRow(
                                titleKey: "devTools.performance.cls",
                                value: formattedCLS(metrics.cumulativeLayoutShift)
                            ),
                        ]
                    )

                    perfMetricsSection(
                        titleKey: "devTools.performance.accessibility",
                        rows: [
                            PerfMetricRow(
                                titleKey: "devTools.performance.imagesMissingAlt",
                                value: "\(metrics.imagesMissingAltCount)"
                            ),
                            PerfMetricRow(
                                titleKey: "devTools.performance.buttonsMissingLabel",
                                value: "\(metrics.buttonsMissingLabelCount)"
                            ),
                            PerfMetricRow(
                                titleKey: "devTools.performance.inputsMissingLabel",
                                value: "\(metrics.inputsMissingLabelCount)"
                            ),
                        ]
                    )
                }
                .padding(20)
            }
        } else {
            emptyState(labelKey: "devTools.performance.empty")
        }
    }

    private struct PerfMetricRow: Identifiable {
        let id = UUID()
        let titleKey: LocalizedStringKey
        let value: String
    }

    private func perfMetricsSection(titleKey: LocalizedStringKey, rows: [PerfMetricRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                HStack {
                    Text(row.titleKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: row.value)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func formattedMilliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f ms", value)
    }

    private func formattedCLS(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value)
    }

    // MARK: - Element inspector (Phase 16)

    private var inspectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("devTools.inspector.enable", isOn: $viewModel.isElementInspectorEnabled)
                .toggleStyle(.checkbox)

            if let element = viewModel.inspectedElement {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: elementSummary(element))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)

                    boxModelRow(labelKey: "devTools.inspector.size", value: String(
                        format: "%.0f × %.0f", element.width, element.height
                    ))
                    boxModelRow(labelKey: "devTools.inspector.margin", value: element.margin)
                    boxModelRow(labelKey: "devTools.inspector.border", value: element.border)
                    boxModelRow(labelKey: "devTools.inspector.padding", value: element.padding)
                    boxModelRow(labelKey: "devTools.inspector.font", value: element.fontSize)
                    boxModelRow(labelKey: "devTools.inspector.color", value: element.color)
                }
                .padding(.top, 4)

                Spacer()
            } else {
                emptyState(labelKey: "devTools.inspector.empty")
            }
        }
        .padding(20)
    }

    private func elementSummary(_ element: ElementBoxModel) -> String {
        var summary = "<\(element.tagName)"
        if let id = element.elementID, !id.isEmpty {
            summary += "#\(id)"
        }
        if let className = element.className, !className.isEmpty {
            summary += ".\(className.split(separator: " ").joined(separator: "."))"
        }
        summary += ">"
        return summary
    }

    private func boxModelRow(labelKey: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(labelKey)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(verbatim: value)
                .font(.caption2)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
    }
}
