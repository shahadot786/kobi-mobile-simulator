//
//  WebViewRepresentable.swift
//  Kobi
//

import SwiftUI
import WebKit

private let scrollSyncMessageHandlerName = "kobiScrollSync"

private let scrollSyncScriptSource = """
(function() {
    var reportScroll = function() {
        var maxX = document.documentElement.scrollWidth - window.innerWidth;
        var maxY = document.documentElement.scrollHeight - window.innerHeight;
        var fractionX = maxX > 0 ? window.scrollX / maxX : 0;
        var fractionY = maxY > 0 ? window.scrollY / maxY : 0;
        window.webkit.messageHandlers.\(scrollSyncMessageHandlerName).postMessage({ x: fractionX, y: fractionY });
    };
    var scheduled = false;
    window.addEventListener('scroll', function() {
        if (scheduled) { return; }
        scheduled = true;
        window.requestAnimationFrame(function() {
            reportScroll();
            scheduled = false;
        });
    }, { passive: true });
})();
"""

/// Lets kiosk/PWA-preview mode reflect in `(display-mode: standalone)` media queries, since
/// WKWebView always reports as a regular browser tab otherwise — pages that branch on install
/// state (hiding an "Add to Home Screen" prompt, etc.) can be previewed accurately.
private let pwaDisplayModeScriptSource = """
(function() {
    window.__kobiStandalone = false;
    var originalMatchMedia = window.matchMedia.bind(window);
    window.matchMedia = function(query) {
        if (typeof query === 'string' && query.indexOf('display-mode') !== -1) {
            var matches = window.__kobiStandalone && query.indexOf('standalone') !== -1;
            return {
                matches: matches,
                media: query,
                onchange: null,
                addListener: function() {},
                removeListener: function() {},
                addEventListener: function() {},
                removeEventListener: function() {},
                dispatchEvent: function() { return true; }
            };
        }
        return originalMatchMedia(query);
    };
    window.__kobiSetStandalone = function(value) {
        window.__kobiStandalone = value;
    };
})();
"""

struct WebViewRepresentable: NSViewRepresentable {
    let viewModel: SimulatorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: scrollSyncMessageHandlerName)
        contentController.add(context.coordinator, name: keyboardVisibilityMessageHandlerName)
        contentController.addUserScript(
            WKUserScript(source: scrollSyncScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(source: touchDispatchScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(source: pwaDisplayModeScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(
                source: keyboardVisibilityScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = viewModel.device.userAgent
        viewModel.webView = webView

        let overlay = TouchSimulationOverlayView()
        overlay.webView = webView
        overlay.isHidden = !viewModel.isTouchSimulationEnabled
        overlay.frame = webView.bounds
        overlay.autoresizingMask = [.width, .height]
        webView.addSubview(overlay)
        context.coordinator.touchOverlay = overlay

        let keyboardOverlay = NSHostingView(rootView: MockKeyboardView())
        keyboardOverlay.isHidden = true
        webView.addSubview(keyboardOverlay)
        context.coordinator.keyboardOverlay = keyboardOverlay

        if let url = viewModel.currentURL {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.customUserAgent != viewModel.device.userAgent {
            webView.customUserAgent = viewModel.device.userAgent
        }
        context.coordinator.touchOverlay?.isHidden = !viewModel.isTouchSimulationEnabled
        webView.evaluateJavaScript(
            "window.__kobiSetStandalone && window.__kobiSetStandalone(\(viewModel.isKioskModeEnabled))"
        )

        if let keyboardOverlay = context.coordinator.keyboardOverlay {
            let height = min(webView.bounds.height * 0.38, 260)
            keyboardOverlay.frame = CGRect(
                x: 0,
                y: webView.isFlipped ? webView.bounds.height - height : 0,
                width: webView.bounds.width,
                height: height
            )
            keyboardOverlay.isHidden = !(viewModel.isKeyboardOverlayEnabled && viewModel.isKeyboardOverlayVisible)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator _: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: scrollSyncMessageHandlerName)
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: keyboardVisibilityMessageHandlerName)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let viewModel: SimulatorViewModel
        var touchOverlay: TouchSimulationOverlayView?
        var keyboardOverlay: NSHostingView<MockKeyboardView>?

        init(viewModel: SimulatorViewModel) {
            self.viewModel = viewModel
        }

        func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            viewModel.isLoading = true
            viewModel.loadError = nil
            viewModel.isKeyboardOverlayVisible = false
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            viewModel.isLoading = false
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward
            // A fresh document re-runs the PWA shim's `atDocumentStart` script, which resets
            // its standalone flag to false — re-sync it now that the new document exists.
            webView.evaluateJavaScript(
                "window.__kobiSetStandalone && window.__kobiSetStandalone(\(viewModel.isKioskModeEnabled))"
            )
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
            viewModel.loadError = error.localizedDescription
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
            viewModel.loadError = error.localizedDescription
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }

            switch message.name {
            case scrollSyncMessageHandlerName:
                guard let fractionX = body["x"] as? Double, let fractionY = body["y"] as? Double else { return }
                viewModel.reportScroll(fractionX: fractionX, fractionY: fractionY)
            case keyboardVisibilityMessageHandlerName:
                guard let visible = body["visible"] as? Bool else { return }
                viewModel.isKeyboardOverlayVisible = visible
            default:
                break
            }
        }
    }
}
