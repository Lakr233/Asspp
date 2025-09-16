//
//  SearchView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct SearchView: View {
    @AppStorage("searchKey") var searchKey = ""
    @AppStorage("searchRegion") var searchRegion = "US"
    @FocusState var searchKeyFocused
    @State var searchType = EntityType.iPhone

    @State var searching = false
    let regionKeys = Array(ApplePackage.Configuration.storeFrontValues.keys.sorted())

    @State var searchInput: String = ""
    #if DEBUG
    @AppStorage("searchResults") // reduce API calls
    var searchResult: [AppStore.AppPackage] = []
    #else
    @State var searchResult: [AppStore.AppPackage] = []
    #endif

    @StateObject var vm = AppStore.this

    var possibleRegion: Set<String> {
        vm.possibleRegions
    }

    var body: some View {
        NavigationView {
            content
                .searchable(text: $searchKey, prompt: "Keyword") {}
                .onSubmit(of: .search) { search() }
                .navigationTitle("Search - \(searchRegion.uppercased())")
                .toolbar { tools }
        }
    }

    @ToolbarContentBuilder
    var tools: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(selection: $searchType) {
                    ForEach(EntityType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                } label: {
                    Label("Type", systemImage: searchType.iconName)
                }
                .pickerStyle(.menu)
                if !regionKeys.filter({ possibleRegion.contains($0) }).isEmpty {
                    buildPickView(
                        for: regionKeys.filter { possibleRegion.contains($0) }
                    ) {
                        Label("Available Regions", systemImage: "checkmark.seal")
                    }
                }
                Menu {
                    buildPickView(
                        for: regionKeys
                    ) {
                        EmptyView()
                    }
                } label: {
                    Label("All Regions", systemImage: "globe")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    var content: some View {
        List {
            if searching || !searchResult.isEmpty {
                Section(searching ? "Searching..." : "\(searchResult.count) Results") {
                    ForEach(searchResult) { item in
                        NavigationLink(destination: ProductView(archive: item, region: searchRegion)) {
                            ArchivePreviewView(archive: item)
                        }
                    }
                    .transition(.opacity)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring, value: searchResult)
        .onChange(of: searchRegion) { _ in
            searchResult = []
        }
        .onChange(of: searchType) { _ in
            searchResult = []
        }
    }

    func buildPickView(for keys: [String], label: () -> some View) -> some View {
        Picker(selection: $searchRegion) {
            ForEach(keys, id: \.self) { key in
                Text("\(key) - \(ApplePackage.Configuration.storeFrontValues[key] ?? String(localized: "Unknown"))")
                    .tag(key)
            }
        } label: {
            label()
        }
    }

    func search() {
        searchKeyFocused = false
        searching = true
        searchInput = "\(searchRegion) - \(searchKey)" + " ..."
        Task {
            do {
                var result = try await ApplePackage.Searcher.search(
                    term: searchKey,
                    countryCode: searchRegion,
                    limit: 32,
                    entityType: searchType
                )
                if let app = try? await ApplePackage.Lookup.lookup(
                    bundleID: searchKey,
                    countryCode: searchRegion
                ) {
                    result.insert(app, at: 0)
                }
                await MainActor.run {
                    searching = false
                    searchResult = result.map { AppStore.AppPackage(software: $0) }
                    searchInput = "\(searchRegion) - \(searchKey)"
                }
            } catch {
                await MainActor.run {
                    searching = false
                    searchResult = []
                    searchInput = "\(searchRegion) - \(searchKey) - Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

#if DEBUG
private typealias AppPackages = [AppStore.AppPackage]
extension AppPackages: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        guard
            let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([AppStore.AppPackage].self, from: data)
        else { return nil }

        self = decoded
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let rawValue = String(data: data, encoding: .utf8)
        else { return "" }

        return rawValue
    }
}
#endif

extension ApplePackage.EntityType {
    var iconName: String {
        switch self {
        case .iPhone:
            "iphone"
        case .iPad:
            "ipad"
        }
    }
}
