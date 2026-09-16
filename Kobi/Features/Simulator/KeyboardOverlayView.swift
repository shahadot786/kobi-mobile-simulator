//
//  KeyboardOverlayView.swift
//  Kobi
//
//  Phase 5 — native-keyboard overlay simulation. `WKWebView` already routes real keystrokes
//  straight into whatever page element has focus, so this overlay is purely visual: a mock
//  on-screen keyboard that covers the bottom of the viewport whenever a text input/textarea/
//  contenteditable element is focused, mirroring how a real mobile OS keyboard covers part of
//  the screen — useful for catching "submit button hidden behind the keyboard" layout bugs.
//

import AppKit
import SwiftUI
import WebKit

let keyboardVisibilityMessageHandlerName = "kobiKeyboardVisibility"

let keyboardVisibilityScriptSource = """
(function() {
    function isTextInput(el) {
        if (!el) { return false; }
        var tag = el.tagName ? el.tagName.toLowerCase() : '';
        if (tag === 'textarea') { return true; }
        if (el.isContentEditable) { return true; }
        if (tag === 'input') {
            var type = (el.getAttribute('type') || 'text').toLowerCase();
            var textTypes = ['text', 'email', 'tel', 'url', 'search', 'password', 'number'];
            return textTypes.indexOf(type) !== -1;
        }
        return false;
    }
    function report(visible) {
        window.webkit.messageHandlers.\(keyboardVisibilityMessageHandlerName).postMessage({ visible: visible });
    }
    document.addEventListener('focusin', function(event) {
        if (isTextInput(event.target)) { report(true); }
    }, true);
    document.addEventListener('focusout', function(event) {
        if (isTextInput(event.target)) { report(false); }
    }, true);
})();
"""

/// A static, non-interactive mock of a mobile on-screen keyboard. Real keystrokes still go
/// straight to the focused page element via the actual Mac keyboard — this view only occupies
/// the screen space a real keyboard would, so developers can see what it covers.
struct MockKeyboardView: View {
    private let rowWeights: [[CGFloat]] = [
        Array(repeating: 1, count: 10),
        Array(repeating: 1, count: 9),
        [1.5] + Array(repeating: 1, count: 7) + [1.5],
        [1.2, 1, 1, 5, 1, 1, 1.2]
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)

                VStack(spacing: 6) {
                    ForEach(rowWeights.indices, id: \.self) { rowIndex in
                        row(weights: rowWeights[rowIndex], totalWidth: proxy.size.width - 16, spacing: 5)
                    }
                }
                .padding(8)

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .accessibilityHidden(true)
    }

    private func row(weights: [CGFloat], totalWidth: CGFloat, spacing: CGFloat) -> some View {
        let totalWeight = weights.reduce(0, +)
        let totalSpacing = spacing * CGFloat(weights.count - 1)
        let availableWidth = max(totalWidth - totalSpacing, 0)

        return HStack(spacing: spacing) {
            ForEach(weights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: availableWidth * weights[index] / totalWeight, height: 28)
            }
        }
    }
}
