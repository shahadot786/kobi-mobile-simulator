//
//  GestureSimulationOverlay.swift
//  Kobi
//
//  Phase 5 — touch/gesture simulation. Desktop WebKit (what WKWebView uses on macOS) doesn't
//  implement the `Touch`/`TouchEvent` JS APIs at all — that's compiled out on the Mac, unlike
//  iOS WebKit. Real touch-aware code paths on the web mostly check Pointer Events
//  (`pointerType === 'touch'`) for exactly this cross-platform reason, so that's the primary
//  signal this overlay dispatches; `TouchEvent` is also attempted, feature-detected, for pages
//  that specifically need it (a no-op wherever the constructor doesn't exist).
//

import AppKit
import WebKit

let touchDispatchScriptSource = """
(function() {
    var activePointerId = 1;

    function dispatchPointer(type, x, y) {
        var target = document.elementFromPoint(x, y) || document.documentElement;
        var event = new PointerEvent(type, {
            pointerId: activePointerId,
            pointerType: 'touch',
            isPrimary: true,
            clientX: x,
            clientY: y,
            bubbles: true,
            cancelable: true,
            composed: true
        });
        target.dispatchEvent(event);

        if (typeof window.TouchEvent === 'function' && typeof window.Touch === 'function') {
            try {
                var touch = new Touch({
                    identifier: activePointerId,
                    target: target,
                    clientX: x,
                    clientY: y,
                    pageX: x + window.scrollX,
                    pageY: y + window.scrollY
                });
                var touchType = type === 'pointerdown' ? 'touchstart' : type === 'pointermove' ? 'touchmove' : 'touchend';
                var touches = touchType === 'touchend' ? [] : [touch];
                var touchEvent = new TouchEvent(touchType, {
                    touches: touches,
                    targetTouches: touches,
                    changedTouches: [touch],
                    bubbles: true,
                    cancelable: true
                });
                target.dispatchEvent(touchEvent);
            } catch (error) {}
        }
    }

    function dispatchContextMenu(x, y) {
        var target = document.elementFromPoint(x, y) || document.documentElement;
        target.dispatchEvent(new MouseEvent('contextmenu', {
            clientX: x,
            clientY: y,
            bubbles: true,
            cancelable: true
        }));
    }

    window.__kobiDispatchPointer = dispatchPointer;
    window.__kobiDispatchContextMenu = dispatchContextMenu;
})();
"""

/// Sits on top of the `WKWebView` as a subview, only hit-testable while touch simulation is
/// on. Trackpad pinch (`magnify`) and two-finger scroll (`scrollWheel`) are deliberately left
/// un-overridden — WebKit already forwards those to the page as native `gesturestart`/
/// `gesturechange`/`gestureend` and `wheel` events, so re-implementing them here would risk
/// double-handling something that already works.
final class TouchSimulationOverlayView: NSView {
    weak var webView: WKWebView?

    private var longPressTimer: Timer?
    private var didMove = false

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        didMove = false
        let point = convert(event.locationInWindow, from: nil)
        dispatchPointer(type: "pointerdown", point: point)

        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self, !self.didMove else { return }
            self.dispatchContextMenu(point: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        didMove = true
        longPressTimer?.invalidate()
        longPressTimer = nil
        let point = convert(event.locationInWindow, from: nil)
        dispatchPointer(type: "pointermove", point: point)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        longPressTimer?.invalidate()
        longPressTimer = nil
        let point = convert(event.locationInWindow, from: nil)
        dispatchPointer(type: "pointerup", point: point)
    }

    private func dispatchPointer(type: String, point: NSPoint) {
        webView?.evaluateJavaScript(
            "window.__kobiDispatchPointer && window.__kobiDispatchPointer('\(type)', \(point.x), \(point.y))"
        )
    }

    private func dispatchContextMenu(point: NSPoint) {
        webView?.evaluateJavaScript(
            "window.__kobiDispatchContextMenu && window.__kobiDispatchContextMenu(\(point.x), \(point.y))"
        )
    }
}
