//
//  SimulatorViewModel.swift
//  Kobi
//

import Foundation
import Observation
import WebKit

enum ZoomOption: CaseIterable, Identifiable {
    case fit
    case percent50
    case percent75
    case percent100
    case percent125
    case percent150

    var id: Self {
        self
    }

    /// `nil` means "fit to window" — the effective scale is computed from available space.
    var fixedScale: CGFloat? {
        switch self {
        case .fit: nil
        case .percent50: 0.5
        case .percent75: 0.75
        case .percent100: 1.0
        case .percent125: 1.25
        case .percent150: 1.5
        }
    }

    var label: String {
        switch self {
        case .fit: "Fit"
        case .percent50: "50%"
        case .percent75: "75%"
        case .percent100: "100%"
        case .percent125: "125%"
        case .percent150: "150%"
        }
    }
}

/// A relayed click or form-input event — see Phase 12 in docs/ROADMAP_V2.md.
struct InteractionSyncEvent {
    let type: String
    let selector: String
    let value: String?
}

@Observable
final class SimulatorViewModel: Identifiable {
    let id = UUID()

    var device: Device
    var orientation: DeviceOrientation = .portrait
    var zoomOption: ZoomOption = .fit
    var isFrameVisible: Bool = true
    var isTouchSimulationEnabled: Bool = false
    var isKioskModeEnabled: Bool = false
    var isKeyboardOverlayEnabled: Bool = false
    var isKeyboardOverlayVisible: Bool = false

    var networkThrottlePreset: NetworkThrottlePreset = .none {
        didSet {
            guard oldValue != networkThrottlePreset else { return }
            applyProxyRouting()
        }
    }

    /// When on, requests are routed through `ThrottleProxyServer` purely to log them (method,
    /// status, timing, size) even at full speed — independent of whether throttling itself is
    /// also on. See Phase 10 in docs/ROADMAP_V2.md.
    var isNetworkLoggingEnabled: Bool = false {
        didSet {
            guard oldValue != isNetworkLoggingEnabled else { return }
            applyProxyRouting()
        }
    }

    /// Polls the loaded document for changes and auto-reloads on change — see
    /// `AutoReloadMonitor` and Phase 12 in docs/ROADMAP_V2.md.
    var isWatchModeEnabled: Bool = false {
        didSet {
            guard oldValue != isWatchModeEnabled else { return }
            applyWatchMode()
        }
    }

    private static let maxLogEntries = 300

    private(set) var consoleLogEntries: [ConsoleLogEntry] = []
    private(set) var networkLogEntries: [NetworkLogEntry] = []
    private(set) var perfMetrics: PerfMetricsSnapshot?
    private(set) var inspectedElement: ElementBoxModel?

    var jsErrorCount: Int {
        consoleLogEntries.filter { $0.level == .error }.count
    }

    /// Hover-to-highlight + click-to-inspect box model — Phase 16. Toggling this on makes the
    /// page's own click handling stop working (the injected script intercepts clicks to report
    /// the target element instead), matching how real DevTools' inspect mode behaves.
    var isElementInspectorEnabled: Bool = false {
        didSet {
            guard oldValue != isElementInspectorEnabled else { return }
            if !isElementInspectorEnabled {
                inspectedElement = nil
            }
            webView?.evaluateJavaScript(
                "window.__kobiSetInspectorEnabled && window.__kobiSetInspectorEnabled(\(isElementInspectorEnabled))"
            )
        }
    }

    var urlString: String
    private(set) var currentURL: URL?

    var isLoading: Bool = false
    var loadError: String?
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    /// True while this frame is scrolled out of the canvas viewport and lazy-suspended — see
    /// Phase 13 in docs/ROADMAP_V2.md. Best-effort: dispatches a standards-based
    /// `visibilitychange` signal (many pages already pause their own polling/animations on
    /// `document.hidden`) and freezes CSS animations/transitions directly. It does not force a
    /// hard stop of arbitrary page JS — WebKit has no public API for that — and deliberately
    /// avoids unloading the page, which would lose scroll position and in-page state every time
    /// a card scrolls in and out of view.
    private(set) var isSuspended = false

    weak var webView: WKWebView?
    private var throttleProxy: ThrottleProxyServer?
    private let autoReloadMonitor = AutoReloadMonitor()

    /// Reports fractional scroll position (0...1 on each axis) whenever this frame's page
    /// scrolls, so a canvas of multiple frames can mirror scrolling across them.
    var onScrollFraction: ((Double, Double) -> Void)?

    /// Reports a click or form-input event so a canvas of multiple frames can replay a flow
    /// tested once across every open device — Phase 12.
    var onInteraction: ((InteractionSyncEvent) -> Void)?

    /// Set right before we programmatically scroll this frame in response to another frame's
    /// scroll, so the resulting 'scroll' event doesn't get reported back out and cause an
    /// infinite ping-pong between synced frames.
    private var isApplyingSyncedScroll = false

    init(device: Device, initialURLString: String = "http://localhost:3000") {
        self.device = device
        urlString = initialURLString
        currentURL = URL(string: Self.normalizedURLString(from: initialURLString))
    }

    deinit {
        throttleProxy?.stop()
        autoReloadMonitor.stop()
    }

    func toggleOrientation() {
        orientation = orientation == .portrait ? .landscape : .portrait
    }

    func submitURL() {
        load(urlString: urlString)
    }

    func reload() {
        webView?.reload()
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func load(urlString: String) {
        let normalized = Self.normalizedURLString(from: urlString)
        guard let url = URL(string: normalized), url.host != nil else {
            loadError = String(localized: "simulator.error.invalidURL")
            return
        }
        self.urlString = urlString
        currentURL = url
        if shouldRouteThroughProxy {
            reloadThroughProxy()
        } else {
            webView?.load(URLRequest(url: url))
        }
        if isWatchModeEnabled {
            applyWatchMode()
        }
    }

    // MARK: - Console / JS error / network logs

    func appendConsoleLog(level: ConsoleLogLevel, message: String) {
        consoleLogEntries.append(ConsoleLogEntry(level: level, message: message, timestamp: Date()))
        if consoleLogEntries.count > Self.maxLogEntries {
            consoleLogEntries.removeFirst(consoleLogEntries.count - Self.maxLogEntries)
        }
    }

    func appendNetworkLog(_ entry: NetworkLogEntry) {
        networkLogEntries.append(entry)
        if networkLogEntries.count > Self.maxLogEntries {
            networkLogEntries.removeFirst(networkLogEntries.count - Self.maxLogEntries)
        }
    }

    /// Called on every navigation start so logs reflect only the current page, matching how
    /// Safari/Chrome DevTools clear their console and network panels by default on reload.
    func clearLogsForNewNavigation() {
        consoleLogEntries.removeAll()
        networkLogEntries.removeAll()
        perfMetrics = nil
    }

    func clearConsoleLogs() {
        consoleLogEntries.removeAll()
    }

    func clearNetworkLogs() {
        networkLogEntries.removeAll()
    }

    // MARK: - Performance / a11y metrics (Phase 16)

    func updatePerfMetrics(_ snapshot: PerfMetricsSnapshot) {
        perfMetrics = snapshot
    }

    /// Re-runs the injected metrics pass on demand, without waiting for a fresh page load.
    func refreshPerfMetrics() {
        webView?.evaluateJavaScript("window.__kobiComputePerfMetrics && window.__kobiComputePerfMetrics()")
    }

    // MARK: - Element inspector (Phase 16)

    func updateInspectedElement(_ element: ElementBoxModel) {
        inspectedElement = element
    }

    // MARK: - Watch mode (auto-reload)

    private func applyWatchMode() {
        guard isWatchModeEnabled, let currentURL else {
            autoReloadMonitor.stop()
            return
        }
        autoReloadMonitor.start(url: currentURL) { [weak self] in
            self?.reload()
        }
    }

    // MARK: - Lazy-suspend (Phase 13)

    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        webView?.evaluateJavaScript("window.__kobiSetSuspended && window.__kobiSetSuspended(true)")
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        webView?.evaluateJavaScript("window.__kobiSetSuspended && window.__kobiSetSuspended(false)")
    }

    // MARK: - Network throttling / logging proxy

    private var shouldRouteThroughProxy: Bool {
        networkThrottlePreset != .none || isNetworkLoggingEnabled
    }

    private func applyProxyRouting() {
        guard shouldRouteThroughProxy else {
            throttleProxy?.stop()
            throttleProxy = nil
            if let currentURL {
                webView?.load(URLRequest(url: currentURL))
            }
            return
        }
        reloadThroughProxy()
    }

    /// The URL bar always shows the real address the user typed — only the `WKWebView`'s
    /// actual request target gets rewritten to point at the local proxy.
    private func reloadThroughProxy() {
        guard let url = currentURL else { return }
        guard url.scheme == "http", let host = url.host else {
            loadError = String(localized: "simulator.error.throttleRequiresHTTP")
            networkThrottlePreset = .none
            return
        }

        let upstreamPort = UInt16(url.port ?? 80)
        let proxy = throttleProxy ?? ThrottleProxyServer()
        proxy.onRequestLogged = { [weak self] entry in
            Task { @MainActor in
                self?.appendNetworkLog(entry)
            }
        }
        throttleProxy = proxy
        let preset = networkThrottlePreset

        Task { [weak self] in
            guard let self else { return }
            do {
                let localPort = try await proxy.start(upstreamHost: host, upstreamPort: upstreamPort, preset: preset)
                // The preset (or the whole target) may have changed again while `start` was
                // still resolving — if so, this now-stale result shouldn't clobber it.
                guard networkThrottlePreset == preset else { return }
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.host = "127.0.0.1"
                components?.port = Int(localPort)
                guard let proxiedURL = components?.url else { return }
                webView?.load(URLRequest(url: proxiedURL))
            } catch {
                loadError = error.localizedDescription
                networkThrottlePreset = .none
            }
        }
    }

    /// Called by the receiving webview's scroll listener; ignored while `isApplyingSyncedScroll`
    /// is set, so it doesn't re-broadcast a scroll we just applied on this frame's behalf.
    func reportScroll(fractionX: Double, fractionY: Double) {
        guard !isApplyingSyncedScroll else { return }
        onScrollFraction?(fractionX, fractionY)
    }

    func scrollTo(fractionX: Double, fractionY: Double) {
        isApplyingSyncedScroll = true
        let js = """
        (function() {
            var maxX = document.documentElement.scrollWidth - window.innerWidth;
            var maxY = document.documentElement.scrollHeight - window.innerHeight;
            window.scrollTo(Math.max(maxX, 0) * \(fractionX), Math.max(maxY, 0) * \(fractionY));
        })();
        """
        webView?.evaluateJavaScript(js) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.isApplyingSyncedScroll = false
            }
        }
    }

    // MARK: - Cross-device interaction sync (click / form input)

    /// Called by the receiving webview's interaction listener — unlike scroll, the injected
    /// script already suppresses re-capture while replaying (see `interactionSyncScriptSource`
    /// in `WebViewRepresentable.swift`), so no Swift-side re-entrancy guard is needed here.
    func reportInteraction(_ event: InteractionSyncEvent) {
        onInteraction?(event)
    }

    func applyInteraction(_ event: InteractionSyncEvent) {
        let type = Self.jsStringLiteral(event.type)
        let selector = Self.jsStringLiteral(event.selector)
        let value = event.value.map { Self.jsStringLiteral($0) } ?? "null"
        webView?.evaluateJavaScript(
            "window.__kobiApplyInteraction && window.__kobiApplyInteraction(\(type), \(selector), \(value))"
        )
    }

    /// Encodes a Swift string as a safely-escaped, quoted JS string literal for embedding in an
    /// `evaluateJavaScript` call — selectors/values come from arbitrary page content, so naive
    /// string interpolation would be a JS-injection risk.
    private static func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string), let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }

    private static func normalizedURLString(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return trimmed
        }
        let isLocal = trimmed.hasPrefix("localhost")
            || trimmed.range(of: #"^\d{1,3}(\.\d{1,3}){3}"#, options: .regularExpression) != nil
        return (isLocal ? "http://" : "https://") + trimmed
    }
}
