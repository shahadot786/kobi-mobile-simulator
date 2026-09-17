//
//  DevicePickerView.swift
//  Kobi
//
//  Phase 7 — Polish, search empty states, and accessibility
//

import SwiftUI

struct DevicePickerView: View {
    @Bindable var store: DeviceCatalogStore
    let isSelected: (Device) -> Bool
    let onSelect: (Device) -> Void

    @State private var isAddingCustomDevice = false
    @State private var deviceForDetail: Device?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            categoryPicker
            Divider()

            if store.filteredDevices.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("deviceCatalog.search.empty.title")
                        .font(.caption.weight(.medium))
                    if !store.searchText.isEmpty {
                        Button("deviceCatalog.search.empty.clear") {
                            store.searchText = ""
                        }
                        .font(.caption)
                    }
                    Spacer()

                    Button {
                        isAddingCustomDevice = true
                    } label: {
                        Label("deviceCatalog.action.addCustomDevice", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.filteredDevices) { device in
                        DeviceRowView(
                            device: device,
                            isSelected: isSelected(device),
                            isFavorite: store.isFavorite(device),
                            onSelect: { onSelect(device) },
                            onToggleFavorite: { store.toggleFavorite(device) },
                            onShowDetail: { deviceForDetail = device }
                        )
                        .swipeActions(edge: .trailing) {
                            if store.customDevices.contains(where: { $0.id == device.id }) {
                                Button(role: .destructive) {
                                    store.removeCustomDevice(device)
                                } label: {
                                    Label("deviceCatalog.action.delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        isAddingCustomDevice = true
                    } label: {
                        Label("deviceCatalog.action.addCustomDevice", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(isPresented: $isAddingCustomDevice) {
            AddCustomDeviceView(store: store)
        }
        .popover(item: $deviceForDetail) { device in
            DeviceDetailPopover(device: device) {
                onSelect(device)
                deviceForDetail = nil
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("deviceCatalog.search.placeholder", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("deviceCatalog.search.placeholder")

            Button {
                store.showFavoritesOnly.toggle()
            } label: {
                Image(systemName: store.showFavoritesOnly ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.showFavoritesOnly ? .yellow : .secondary)
            .help("deviceCatalog.action.favoritesOnly")
            .accessibilityLabel("deviceCatalog.action.favoritesOnly")
        }
        .padding(8)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(title: "deviceCatalog.category.all", isSelected: store.selectedCategory == nil) {
                    store.selectedCategory = nil
                }
                ForEach(DeviceCategory.allCases, id: \.self) { category in
                    categoryChip(title: category.titleKey, isSelected: store.selectedCategory == category) {
                        store.selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 4)
    }

    private func categoryChip(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.accentColor.opacity(0.2) : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
