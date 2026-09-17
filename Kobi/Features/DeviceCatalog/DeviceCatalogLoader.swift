//
//  DeviceCatalogLoader.swift
//  Kobi
//

import Foundation

enum DeviceCatalogLoader {
    static func loadSeedDevices() -> [Device] {
        guard let url = Bundle.main.url(forResource: "DeviceCatalog", withExtension: "json") else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Device].self, from: data)
        } catch {
            return []
        }
    }
}
