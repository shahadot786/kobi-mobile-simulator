//
//  WebViewRepresentable.swift
//  Kobi
//

import SwiftUI
import WebKit

private let scrollSyncMessageHandlerName = "kobiScrollSync"
private let consoleMessageHandlerName = "kobiConsole"
private let interactionSyncMessageHandlerName = "kobiInteractionSync"
private let perfMetricsMessageHandlerName = "kobiPerfMetrics"
private let elementInspectorMessageHandlerName = "kobiElementInspector"

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

/// Best-effort lazy-suspend for cards scrolled out of the canvas viewport (Phase 13). Dispatches
/// the standards-based Page Visibility signal (`document.hidden`/`visibilitychange`) — pages
/// that already pause their own polling/animation loops in background tabs get that benefit
/// here too — and freezes CSS animations/transitions directly, which works regardless of
/// whether the page cooperates. This is intentionally not a hard stop of arbitrary JS (no public
/// WebKit API for that) and doesn't unload the page, so scroll position and in-page state
/// survive scrolling a card in and out of view repeatedly.
private let offscreenSuspendScriptSource = """
(function() {
    var styleEl = null;
    window.__kobiSetSuspended = function(suspended) {
        if (suspended) {
            try {
                Object.defineProperty(document, 'hidden', { configurable: true, get: function() { return true; } });
                Object.defineProperty(
                    document, 'visibilityState', { configurable: true, get: function() { return 'hidden'; } }
                );
            } catch (e) {}
            if (!styleEl) {
                styleEl = document.createElement('style');
                styleEl.setAttribute('data-kobi-suspend', 'true');
                styleEl.textContent = '*, *::before, *::after { '
                    + 'animation-play-state: paused !important; transition: none !important; }';
                document.head.appendChild(styleEl);
            }
        } else {
            try {
                delete document.hidden;
                delete document.visibilityState;
            } catch (e) {}
            if (styleEl) {
                styleEl.remove();
                styleEl = null;
            }
        }
        document.dispatchEvent(new Event('visibilitychange'));
    };
})();
"""

/// Core Web Vitals-style timing plus a count-based a11y pass (Phase 16) — not a full Lighthouse
/// port. Runs ~2s after `load` to let Largest Contentful Paint settle (LCP can keep updating
/// until first user interaction), and exposes `window.__kobiComputePerfMetrics` so the Swift
/// side can re-run it on demand without a fresh navigation.
private let perfMetricsScriptSource = """
(function() {
    window.__kobiCLS = 0;
    try {
        new PerformanceObserver(function(list) {
            list.getEntries().forEach(function(entry) {
                if (!entry.hadRecentInput) { window.__kobiCLS += entry.value; }
            });
        }).observe({ type: 'layout-shift', buffered: true });
    } catch (e) {}

    function computeAndSend() {
        try {
            var nav = performance.getEntriesByType('navigation')[0];
            var ttfb = nav ? (nav.responseStart - nav.requestStart) : null;
            var dcl = nav ? (nav.domContentLoadedEventEnd - nav.startTime) : null;
            var loadTime = nav ? (nav.loadEventEnd - nav.startTime) : null;

            var lcpEntries = performance.getEntriesByType('largest-contentful-paint');
            var lcp = lcpEntries.length ? lcpEntries[lcpEntries.length - 1].startTime : null;

            var imagesMissingAlt = 0;
            document.querySelectorAll('img').forEach(function(img) {
                if (!img.hasAttribute('alt') || img.getAttribute('alt').trim() === '') { imagesMissingAlt++; }
            });

            var buttonsMissingLabel = 0;
            document.querySelectorAll('button, [role="button"]').forEach(function(btn) {
                var hasText = btn.textContent && btn.textContent.trim().length > 0;
                var hasAria = btn.hasAttribute('aria-label') || btn.hasAttribute('aria-labelledby');
                if (!hasText && !hasAria) { buttonsMissingLabel++; }
            });

            var inputsMissingLabel = 0;
            document.querySelectorAll('input, textarea, select').forEach(function(el) {
                var type = (el.getAttribute('type') || '').toLowerCase();
                if (type === 'hidden' || type === 'submit' || type === 'button') { return; }
                var id = el.getAttribute('id');
                var hasLabel = id && document.querySelector('label[for="' + id + '"]');
                var hasAria = el.hasAttribute('aria-label') || el.hasAttribute('aria-labelledby');
                if (!hasLabel && !hasAria) { inputsMissingLabel++; }
            });

            window.webkit.messageHandlers.\(perfMetricsMessageHandlerName).postMessage({
                ttfb: ttfb,
                domContentLoaded: dcl,
                load: loadTime,
                lcp: lcp,
                cls: window.__kobiCLS,
                imagesMissingAlt: imagesMissingAlt,
                buttonsMissingLabel: buttonsMissingLabel,
                inputsMissingLabel: inputsMissingLabel
            });
        } catch (e) {}
    }

    window.__kobiComputePerfMetrics = computeAndSend;

    if (document.readyState === 'complete') {
        setTimeout(computeAndSend, 2000);
    } else {
        window.addEventListener('load', function() {
            setTimeout(computeAndSend, 2000);
        });
    }
})();
"""

/// Hover-to-highlight + click-to-inspect box model (Phase 16). While enabled, clicks are
/// intercepted (`preventDefault`/`stopPropagation`) to report the target instead of activating
/// it — the same "inspect mode steals clicks" behavior real browser DevTools have.
private let elementInspectorScriptSource = """
(function() {
    var overlay = null;
    var enabled = false;

    function ensureOverlay() {
        if (overlay) { return overlay; }
        overlay = document.createElement('div');
        overlay.style.position = 'fixed';
        overlay.style.pointerEvents = 'none';
        overlay.style.zIndex = '2147483647';
        overlay.style.background = 'rgba(88, 166, 255, 0.25)';
        overlay.style.border = '1px solid rgba(88, 166, 255, 0.9)';
        overlay.style.display = 'none';
        document.documentElement.appendChild(overlay);
        return overlay;
    }

    function highlight(el) {
        var rect = el.getBoundingClientRect();
        var ov = ensureOverlay();
        ov.style.left = rect.left + 'px';
        ov.style.top = rect.top + 'px';
        ov.style.width = rect.width + 'px';
        ov.style.height = rect.height + 'px';
        ov.style.display = 'block';
    }

    function boxModel(el) {
        var style = window.getComputedStyle(el);
        var rect = el.getBoundingClientRect();
        return {
            tagName: el.tagName.toLowerCase(),
            elementID: el.id || null,
            className: (el.className && typeof el.className === 'string') ? el.className : null,
            width: rect.width,
            height: rect.height,
            margin: [style.marginTop, style.marginRight, style.marginBottom, style.marginLeft].join(' '),
            border: [
                style.borderTopWidth, style.borderRightWidth, style.borderBottomWidth, style.borderLeftWidth
            ].join(' '),
            padding: [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft].join(' '),
            fontSize: style.fontSize,
            color: style.color
        };
    }

    document.addEventListener('mouseover', function(event) {
        if (!enabled) { return; }
        highlight(event.target);
    }, true);

    document.addEventListener('click', function(event) {
        if (!enabled) { return; }
        event.preventDefault();
        event.stopPropagation();
        window.webkit.messageHandlers.\(elementInspectorMessageHandlerName).postMessage(boxModel(event.target));
    }, true);

    window.__kobiSetInspectorEnabled = function(value) {
        enabled = value;
        if (!enabled && overlay) { overlay.style.display = 'none'; }
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
        contentController.add(context.coordinator, name: perfMetricsMessageHandlerName)
        contentController.add(context.coordinator, name: elementInspectorMessageHandlerName)
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
        contentController.addUserScript(
            WKUserScript(
                source: offscreenSuspendScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        contentController.addUserScript(
            WKUserScript(source: perfMetricsScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(
                source: elementInspectorScriptSource,
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
        webView.evaluateJavaScript(
            "window.__kobiSetSuspended && window.__kobiSetSuspended(\(viewModel.isSuspended))"
        )
        webView.evaluateJavaScript(
            "window.__kobiSetInspectorEnabled && window.__kobiSetInspectorEnabled(\(viewModel.isElementInspectorEnabled))"
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: perfMetricsMessageHandlerName)
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: elementInspectorMessageHandlerName)
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
            case perfMetricsMessageHandlerName:
                viewModel.updatePerfMetrics(Self.perfMetrics(from: body))
            case elementInspectorMessageHandlerName:
                guard let element = Self.elementBoxModel(from: body) else { return }
                viewModel.updateInspectedElement(element)
            default:
                break
            }
        }

        private static func perfMetrics(from body: [String: Any]) -> PerfMetricsSnapshot {
            PerfMetricsSnapshot(
                timeToFirstByteMilliseconds: body["ttfb"] as? Double,
                domContentLoadedMilliseconds: body["domContentLoaded"] as? Double,
                loadMilliseconds: body["load"] as? Double,
                largestContentfulPaintMilliseconds: body["lcp"] as? Double,
                cumulativeLayoutShift: body["cls"] as? Double,
                imagesMissingAltCount: body["imagesMissingAlt"] as? Int ?? 0,
                buttonsMissingLabelCount: body["buttonsMissingLabel"] as? Int ?? 0,
                inputsMissingLabelCount: body["inputsMissingLabel"] as? Int ?? 0
            )
        }

        private static func elementBoxModel(from body: [String: Any]) -> ElementBoxModel? {
            guard let tagName = body["tagName"] as? String,
                  let width = body["width"] as? Double,
                  let height = body["height"] as? Double,
                  let margin = body["margin"] as? String,
                  let border = body["border"] as? String,
                  let padding = body["padding"] as? String,
                  let fontSize = body["fontSize"] as? String,
                  let color = body["color"] as? String
            else {
                return nil
            }
            return ElementBoxModel(
                tagName: tagName,
                elementID: body["elementID"] as? String,
                className: body["className"] as? String,
                width: width,
                height: height,
                margin: margin,
                border: border,
                padding: padding,
                fontSize: fontSize,
                color: color
            )
        }
    }
}
