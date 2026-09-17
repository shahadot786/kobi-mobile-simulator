//
//  DeviceCatalogStore.swift
//  Kobi
//

import Foundation
import Observation

/// A brand's devices within the sidebar's grouped list — see Phase 11 in docs/ROADMAP_V2.md.
struct DeviceBrandGroup: Identifiable {
    let brand: String
    let devices: [Device]
    var id: String { brand }
}

@Observable
final class DeviceCatalogStore {
    private(set) var seedDevices: [Device]
    var customDevices: [Device] {
        didSet { persistCustomDevices() }
    }

    var favoriteIDs: Set<String> {
        didSet { persistFavorites() }
    }

    private(set) var recentDeviceIDs: [String] {
        didSet { persistRecentDevices() }
    }

    var searchText: String = ""
    var selectedCategory: DeviceCategory?
    var showFavoritesOnly: Bool = false

    /// When `false`, `filteredDevices` (with no active search) is limited to `curatedDeviceIDs`
    /// so a new user isn't dropped into the full ~30-device catalog at once. Searching always
    /// reaches the full catalog regardless of this toggle.
    var showFullCatalog: Bool = false

    private static let customDevicesKey = "customDevices"
    private static let favoritesKey = "favoriteDeviceIDs"
    private static let recentDevicesKey = "recentDeviceIDs"
    private static let maxRecentDevices = 5

    /// A small, hand-picked set of widely-used devices shown by default before the user opts
    /// into browsing the full catalog via `showFullCatalog`.
    private static let curatedDeviceIDs: Set<String> = [
        "iphone-16-pro-max",
        "iphone-16-pro",
        "iphone-16",
        "iphone-se-3",
        "ipad-pro-12-9",
        "ipad-air-m2",
        "pixel-8-pro",
        "pixel-8",
        "galaxy-s24-ultra",
        "galaxy-s24",
        "apple-watch-series-9-45mm",
        "desktop-1920x1080",
    ]

    init() {
        seedDevices = DeviceCatalogLoader.loadSeedDevices()
        customDevices = Self.loadCustomDevices()
        favoriteIDs = Self.loadFavoriteIDs()
        recentDeviceIDs = Self.loadRecentDeviceIDs()
    }

    var allDevices: [Device] {
        seedDevices + customDevices
    }

    var filteredDevices: [Device] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allDevices.filter { device in
            if showFavoritesOnly, !favoriteIDs.contains(device.id) {
                return false
            }
            if let selectedCategory, device.category != selectedCategory {
                return false
            }
            guard !query.isEmpty else {
                return showFullCatalog || Self.curatedDeviceIDs.contains(device.id)
            }
            if device.name.lowercased().contains(query) {
                return true
            }
            if device.brand.lowercased().contains(query) {
                return true
            }
            if String(device.viewportWidth).contains(query) {
                return true
            }
            if let year = device.releaseYear, String(year).contains(query) {
                return true
            }
            return false
        }
    }

    /// `filteredDevices` grouped by brand, alphabetically — feeds the sidebar's collapsible
    /// brand sections.
    var groupedFilteredDevices: [DeviceBrandGroup] {
        let grouped = Dictionary(grouping: filteredDevices, by: \.brand)
        return grouped.keys.sorted().map { brand in
            DeviceBrandGroup(brand: brand, devices: grouped[brand, default: []].sorted { $0.name < $1.name })
        }
    }

    var recentDevices: [Device] {
        recentDeviceIDs.compactMap { id in allDevices.first { $0.id == id } }
    }

    func recordRecentlyUsed(_ device: Device) {
        var ids = recentDeviceIDs
        ids.removeAll { $0 == device.id }
        ids.insert(device.id, at: 0)
        if ids.count > Self.maxRecentDevices {
            ids.removeLast(ids.count - Self.maxRecentDevices)
        }
        recentDeviceIDs = ids
    }

    func isFavorite(_ device: Device) -> Bool {
        favoriteIDs.contains(device.id)
    }

    func toggleFavorite(_ device: Device) {
        if favoriteIDs.contains(device.id) {
            favoriteIDs.remove(device.id)
        } else {
            favoriteIDs.insert(device.id)
        }
    }

    func addCustomDevice(name: String, category: DeviceCategory, width: Int, height: Int, pixelRatio: Double) {
        let device = Device(
            id: "custom-\(UUID().uuidString)",
            name: name,
            brand: String(localized: "deviceCatalog.customBrand"),
            category: category,
            viewportWidth: width,
            viewportHeight: height,
            pixelRatio: pixelRatio,
            notchStyle: .none,
            userAgent: Self.defaultUserAgent(for: category)
        )
        customDevices.append(device)
    }

    /// A custom device has no real hardware identity to derive a UA string from, but leaving
    /// it empty would make `WKWebView.customUserAgent` send a blank User-Agent header (many
    /// sites gate on it) — so fall back to a generic, plausible UA per category instead.
    private static func defaultUserAgent(for category: DeviceCategory) -> String {
        switch category {
        case .smartphone, .foldable:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .tablet:
            "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        case .wearable:
            "Mozilla/5.0 (Apple Watch; CPU WatchOS 10_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/10.0 Mobile/15E148 Safari/604.1"
        case .desktop:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        }
    }

    func removeCustomDevice(_ device: Device) {
        customDevices.removeAll { $0.id == device.id }
        favoriteIDs.remove(device.id)
        recentDeviceIDs.removeAll { $0 == device.id }
    }

    private func persistCustomDevices() {
        guard let data = try? JSONEncoder().encode(customDevices) else { return }
        UserDefaults.standard.set(data, forKey: Self.customDevicesKey)
    }

    private func persistFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.favoritesKey)
    }

    private func persistRecentDevices() {
        UserDefaults.standard.set(recentDeviceIDs, forKey: Self.recentDevicesKey)
    }

    private static func loadCustomDevices() -> [Device] {
        guard let data = UserDefaults.standard.data(forKey: customDevicesKey),
              let devices = try? JSONDecoder().decode([Device].self, from: data)
        else {
            return []
        }
        return devices
    }

    private static func loadFavoriteIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    private static func loadRecentDeviceIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentDevicesKey) ?? []
    }
}
