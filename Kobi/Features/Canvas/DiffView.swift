//
//  DiffView.swift
//  Kobi
//
//  Phase 16 — cross-device diff: a before/after reveal slider over two already-captured
//  snapshots, to spot layout drift between devices.
//

import SwiftUI

struct DiffView: View {
    let leftImage: NSImage
    let rightImage: NSImage
    let leftLabel: String
    let rightLabel: String
    let onDismiss: () -> Void

    @State private var sliderFraction: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Image(nsImage: rightImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    Image(nsImage: leftImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: proxy.size.width * sliderFraction)
                        }

                    sliderHandle(in: proxy.size)
                }
                .clipped()
                .background(CheckeredBackground())
            }
            .padding(20)

            HStack {
                Text(verbatim: leftLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: rightLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 640, height: 560)
        .background(.regularMaterial)
    }

    private func sliderHandle(in size: CGSize) -> some View {
        let dragGesture = DragGesture(minimumDistance: 0).onChanged { value in
            guard size.width > 0 else { return }
            sliderFraction = min(max(value.location.x / size.width, 0), 1)
        }

        return ZStack {
            Rectangle()
                .fill(KobiTheme.primaryAccent)
                .frame(width: 2)

            Circle()
                .fill(KobiTheme.primaryAccent)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
        .frame(height: size.height)
        .position(x: size.width * sliderFraction, y: size.height / 2)
        .gesture(dragGesture)
        .accessibilityLabel("diffView.sliderLabel")
        .accessibilityValue("\(Int(sliderFraction * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: sliderFraction = min(sliderFraction + 0.05, 1)
            case .decrement: sliderFraction = max(sliderFraction - 0.05, 0)
            default: break
            }
        }
    }

    private var header: some View {
        HStack {
            Text("diffView.title")
                .font(.headline)

            Spacer()

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
}
