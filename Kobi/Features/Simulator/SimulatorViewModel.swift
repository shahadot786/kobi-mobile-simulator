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
            applyThrottlePreset()
        }
    }

    var urlString: String
    private(set) var currentURL: URL?

    var isLoading: Bool = false
    var loadError: String?
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    weak var webView: WKWebView?
    private var throttleProxy: ThrottleProxyServer?

    /// Reports fractional scroll position (0...1 on each axis) whenever this frame's page
    /// scrolls, so a canvas of multiple frames can mirror scrolling across them.
    var onScrollFraction: ((Double, Double) -> Void)?

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
        if networkThrottlePreset == .none {
            webView?.load(URLRequest(url: url))
        } else {
            reloadThroughProxy()
        }
    }

    private func applyThrottlePreset() {
        guard networkThrottlePreset != .none else {
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
