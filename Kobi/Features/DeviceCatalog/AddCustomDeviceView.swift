//
//  AddCustomDeviceView.swift
//  Kobi
//

import SwiftUI

struct AddCustomDeviceView: View {
    let store: DeviceCatalogStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: DeviceCategory = .smartphone
    @State private var width: String = "390"
    @State private var height: String = "844"
    @State private var pixelRatio: String = "2.0"

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let w = Int(width), w > 0 else { return false }
        guard let h = Int(height), h > 0 else { return false }
        guard let dpr = Double(pixelRatio), dpr > 0 else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("deviceCatalog.addCustom.title")
                .font(.headline)

            Form {
                TextField("deviceCatalog.addCustom.name", text: $name)
                Picker("deviceCatalog.addCustom.category", selection: $category) {
                    ForEach(DeviceCategory.allCases, id: \.self) { category in
                        Text(category.titleKey).tag(category)
                    }
                }
                TextField("deviceCatalog.addCustom.width", text: $width)
                TextField("deviceCatalog.addCustom.height", text: $height)
                TextField("deviceCatalog.addCustom.pixelRatio", text: $pixelRatio)
            }

            HStack {
                Spacer()
                Button("deviceCatalog.addCustom.cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("deviceCatalog.addCustom.save") {
                    guard let w = Int(width), let h = Int(height), let dpr = Double(pixelRatio) else { return }
                    store.addCustomDevice(name: name, category: category, width: w, height: h, pixelRatio: dpr)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
