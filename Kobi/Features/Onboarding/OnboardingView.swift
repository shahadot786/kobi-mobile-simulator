//
//  OnboardingView.swift
//  Kobi
//
//  Phase 7 — First-launch onboarding flow: welcoming, device selection, and dev server setup.
//

import SwiftUI

struct OnboardingView: View {
    let catalogStore: DeviceCatalogStore
    let onComplete: (Device, String) -> Void
    let onDismiss: () -> Void

    @State private var currentStep = 0
    @State private var selectedDeviceID: String = "iphone-15-pro"
    @State private var devServerURL: String = "http://localhost:3000"

    private let starterDeviceIDs = [
        "iphone-15-pro",
        "google-pixel-8",
        "samsung-galaxy-s24",
        "ipad-air-11-m2",
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            bottomBar
        }
        .frame(width: 540, height: 440)
    }

    private var topBar: some View {
        HStack {
            // Step Indicators
            HStack(spacing: 6) {
                ForEach(0 ..< 3) { idx in
                    Circle()
                        .fill(idx == currentStep ? KobiTheme.primaryAccent : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            Button("onboarding.button.skip") {
                finish()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            welcomeStep
        case 1:
            devicePickStep
        case 2:
            serverURLStep
        default:
            EmptyView()
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 48))
                .foregroundStyle(KobiTheme.primaryAccent)

            VStack(spacing: 6) {
                Text("onboarding.welcome.title")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("onboarding.welcome.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureItem(
                    icon: "square.grid.2x2",
                    title: "onboarding.feature1.title",
                    detail: "onboarding.feature1.detail"
                )
                featureItem(
                    icon: "gauge.with.dots.needle.33percent",
                    title: "onboarding.feature2.title",
                    detail: "onboarding.feature2.detail"
                )
                featureItem(
                    icon: "camera.viewfinder",
                    title: "onboarding.feature3.title",
                    detail: "onboarding.feature3.detail"
                )
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    private func featureItem(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(KobiTheme.primaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 1: Device Selection

    private var devicePickStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("onboarding.devices.title")
                    .font(.headline)
                Text("onboarding.devices.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(starterDeviceIDs, id: \.self) { devID in
                    if let device = catalogStore.allDevices.first(where: { $0.id == devID }) {
                        deviceCard(device)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func deviceCard(_ device: Device) -> some View {
        let isSelected = device.id == selectedDeviceID

        return Button {
            selectedDeviceID = device.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: device.category == .tablet ? "ipad" : "iphone")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? KobiTheme.primaryAccent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text(
                        verbatim: "\(device.viewportWidth) × \(device.viewportHeight) • \(String(format: "%.1f", device.pixelRatio))×"
                    )
                    .telemetryFont(size: 10)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KobiTheme.primaryAccent)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? KobiTheme.primaryAccent : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Dev Server URL

    private var serverURLStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(KobiTheme.primaryAccent)

            VStack(spacing: 4) {
                Text("onboarding.server.title")
                    .font(.headline)
                Text("onboarding.server.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                TextField("http://localhost:3000", text: $devServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 48)

                // Quick Port presets
                HStack(spacing: 8) {
                    Text("onboarding.server.quickPorts")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    quickPortButton("3000 (Next/React)") { devServerURL = "http://localhost:3000" }
                    quickPortButton("5173 (Vite)") { devServerURL = "http://localhost:5173" }
                    quickPortButton("8080 (Webpack)") { devServerURL = "http://localhost:8080" }
                }
            }

            Spacer()
        }
    }

    private func quickPortButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label) {
            action()
        }
        .buttonStyle(.bordered)
        .font(.system(size: 10))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if currentStep > 0 {
                Button("onboarding.button.back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < 2 {
                Button("onboarding.button.continue") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(KobiTheme.primaryAccent)
            } else {
                Button("onboarding.button.launch") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .tint(KobiTheme.primaryAccent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func finish() {
        let dev = catalogStore.allDevices.first(where: { $0.id == selectedDeviceID })
            ?? catalogStore.allDevices.first
            ?? Device(
                id: "iphone-15-pro",
                name: "iPhone 15 Pro",
                brand: "Apple",
                category: .smartphone,
                viewportWidth: 393,
                viewportHeight: 852,
                pixelRatio: 3.0,
                notchStyle: .dynamicIsland,
                userAgent: "Mozilla/5.0"
            )
        let url = devServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        onComplete(dev, url.isEmpty ? "http://localhost:3000" : url)
    }
}
