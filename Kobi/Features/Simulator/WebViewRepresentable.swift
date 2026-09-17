//
//  WebViewRepresentable.swift
//  Kobi
//

import SwiftUI
import WebKit

private let scrollSyncMessageHandlerName = "kobiScrollSync"
private let consoleMessageHandlerName = "kobiConsole"
private let interactionSyncMessageHandlerName = "kobiInteractionSync"

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

/// Overrides `console.log/info/warn/error` to also forward to Swift, and listens for uncaught
/// errors and unhandled promise rejections — the Phase 10 console/JS-error capture pipeline.
/// Injected `atDocumentStart` so it's in place before any page script can log anything.
private let consoleCaptureScriptSource = """
(function() {
    var send = function(level, args) {
        try {
            var message = Array.prototype.map.call(args, function(value) {
                if (value instanceof Error) { return value.message; }
                if (typeof value === 'object' && value !== null) {
                    try { return JSON.stringify(value); } catch (e) { return String(value); }
                }
                return String(value);
            }).join(' ');
            window.webkit.messageHandlers.\(consoleMessageHandlerName).postMessage({ level: level, message: message });
        } catch (e) {}
    };
    ['log', 'info', 'warn', 'error'].forEach(function(level) {
        var original = console[level] ? console[level].bind(console) : function() {};
        console[level] = function() {
            send(level, arguments);
            original.apply(console, arguments);
        };
    });
    window.addEventListener('error', function(event) {
        send('error', [event.message + ' (' + (event.filename || 'unknown') + ':' + (event.lineno || 0) + ')']);
    });
    window.addEventListener('unhandledrejection', function(event) {
        var reason = event.reason;
        var message = (reason && reason.message) ? reason.message : String(reason);
        send('error', ['Unhandled promise rejection: ' + message]);
    });
})();
"""

/// Reports clicks and form input (with a CSS-path selector for the target) so a canvas of
/// multiple frames can replay the same flow across every open device, and exposes
/// `window.__kobiApplyInteraction` for the Swift side to replay an event it received from
/// another frame. `window.__kobiApplyingInteractionSync` suppresses re-capturing a replayed
/// event, since a synthetic `.click()`/dispatched `input`/`change` event is otherwise
/// indistinguishable from a real one — see Phase 12 in docs/ROADMAP_V2.md.
private let interactionSyncScriptSource = """
(function() {
    function cssPath(el) {
        if (!(el instanceof Element)) { return null; }
        var path = [];
        while (el && el.nodeType === Node.ELEMENT_NODE) {
            var selector = el.nodeName.toLowerCase();
            if (el.id) {
                selector += '#' + el.id;
                path.unshift(selector);
                break;
            }
            var sibling = el, nth = 1;
            while (sibling.previousElementSibling) {
                sibling = sibling.previousElementSibling;
                if (sibling.nodeName.toLowerCase() === el.nodeName.toLowerCase()) { nth++; }
            }
            selector += ':nth-of-type(' + nth + ')';
            path.unshift(selector);
            el = el.parentElement;
        }
        return path.join(' > ');
    }

    window.__kobiApplyingInteractionSync = false;

    document.addEventListener('click', function(event) {
        if (window.__kobiApplyingInteractionSync) { return; }
        var selector = cssPath(event.target);
        if (!selector) { return; }
        window.webkit.messageHandlers.\(interactionSyncMessageHandlerName)
            .postMessage({ type: 'click', selector: selector });
    }, true);

    document.addEventListener('input', function(event) {
        if (window.__kobiApplyingInteractionSync) { return; }
        var selector = cssPath(event.target);
        if (!selector || typeof event.target.value === 'undefined') { return; }
        window.webkit.messageHandlers.\(interactionSyncMessageHandlerName)
            .postMessage({ type: 'input', selector: selector, value: String(event.target.value) });
    }, true);

    window.__kobiApplyInteraction = function(type, selector, value) {
        var el = document.querySelector(selector);
        if (!el) { return; }
        window.__kobiApplyingInteractionSync = true;
        if (type === 'click') {
            el.click();
        } else if (type === 'input') {
            el.value = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
        }
        window.__kobiApplyingInteractionSync = false;
    };
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
        contentController.add(context.coordinator, name: consoleMessageHandlerName)
        contentController.add(context.coordinator, name: interactionSyncMessageHandlerName)
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
        contentController.addUserScript(
            WKUserScript(source: consoleCaptureScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(
                source: interactionSyncScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = viewModel.device.userAgent
        webView.isInspectable = true
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: consoleMessageHandlerName)
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: interactionSyncMessageHandlerName)
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
            viewModel.clearLogsForNewNavigation()
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
            case consoleMessageHandlerName:
                guard let levelString = body["level"] as? String,
                      let level = ConsoleLogLevel(rawValue: levelString),
                      let message = body["message"] as? String else { return }
                viewModel.appendConsoleLog(level: level, message: message)
            case interactionSyncMessageHandlerName:
                guard let type = body["type"] as? String, let selector = body["selector"] as? String else { return }
                let value = body["value"] as? String
                viewModel.reportInteraction(InteractionSyncEvent(type: type, selector: selector, value: value))
            default:
                break
            }
        }
    }
}
