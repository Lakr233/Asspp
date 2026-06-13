//
//  SearchView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

/// Lets menu commands ask the search field to take focus. SearchView consumes
/// the request on its next appearance, or immediately if already visible, and
/// clears it — so the one-shot survives the view being recreated when the user
/// switches sidebar sections.
@MainActor
@Observable
final class SearchFieldFocus {
    static let shared = SearchFieldFocus()
    var pending = false
    func requestFocus() { pending = true }
}

struct SearchView: View {
    @AppStorage("searchKey") var searchKey = ""
    @AppStorage("searchRegion") var searchRegion = "US"
    @FocusState var searchKeyFocused
    @State private var searchFocus = SearchFieldFocus.shared
    @State private var searchType = EntityType.iPhone

    @State private var searching = false
    let regionKeys = Array(ApplePackage.Configuration.storeFrontValues.keys.sorted())

    @State private var searchError: String?
    #if DEBUG
        @AppStorage("searchResults") // reduce API calls
        var searchResult: [AppStore.AppPackage] = []
    #else
        @State private var searchResult: [AppStore.AppPackage] = []
    #endif

    @State private var navigationPath = NavigationPath()
    @State private var vm = AppStore.this
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var possibleRegion: Set<String> {
        vm.possibleRegions
    }

    var body: some View {
        #if os(iOS)
            NavigationStack(path: $navigationPath) {
                if #available(iOS 26.0, *) {
                    modernContent
                } else {
                    legacyContent
                }
            }
        #else
            NavigationStack(path: $navigationPath) {
                legacyContent
            }
        #endif
    }

    var searchTypePicker: some View {
        Picker(selection: $searchType) {
            ForEach(EntityType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        } label: {
            Label("Type", systemImage: searchType.iconName)
        }
        .onChange(of: searchType) { _, _ in
            searchResult = []
        }
    }

    var possibleRegionKeys: [String] {
        regionKeys.filter { possibleRegion.contains($0) }
    }

    func searchRegionView() -> some View {
        Menu {
            if !possibleRegionKeys.isEmpty {
                buildPickView(
                    for: possibleRegionKeys,
                ) {
                    Label("Available Regions", systemImage: "checkmark.seal")
                }
                .pickerStyle(.inline)

                buildPickView(
                    for: regionKeys,
                ) {
                    Label("All Regions", systemImage: "globe")
                }
                .pickerStyle(.menu)
            } else {
                buildPickView(
                    for: regionKeys,
                ) {
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(searchRegion, systemImage: "globe")
        }
        .onChange(of: searchRegion) { _, _ in
            searchResult = []
        }
    }

    @ToolbarContentBuilder
    var tools: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                searchTypePicker
                    .labelsHidden()
                    .pickerStyle(.inline)
            } label: {
                Label("Type", systemImage: searchType.iconName)
            }
            .menuIndicator(.hidden)
        }

        ToolbarItem(placement: .automatic) {
            searchRegionView()
                .menuIndicator(.hidden)
        }
    }

    var content: some View {
        Form {
            if let searchError {
                Section {
                    Text(searchError)
                        .foregroundStyle(.red)
                }
            }
            if searching || !searchResult.isEmpty {
                Section(searching ? "Searching..." : "\(searchResult.count) Results") {
                    ForEach(searchResult) { item in
                        NavigationLink(value: ProductDestination(archive: item, region: searchRegion)) {
                            ArchivePreviewView(archive: item)
                        }
                    }
                    .transition(.opacity)
                }
                .transition(.opacity)
            }
        }
        .formStyle(.grouped)
        .animation(.spring, value: searchError)
        .navigationDestination(for: ProductDestination.self) { dest in
            ProductView(archive: dest.archive, region: dest.region, navigationPath: $navigationPath)
        }
        .navigationDestination(for: PackageManifest.self) { manifest in
            PackageView(pkg: manifest)
        }
        .animation(.spring, value: searchResult)
        .onAppear { consumePendingFocus() }
        .onChange(of: searchFocus.pending) { _, isPending in
            if isPending { consumePendingFocus() }
        }
    }

    /// Focuses the search field if a focus request is pending (e.g. after the
    /// ⌘F menu command on macOS), then clears the request.
    private func consumePendingFocus() {
        guard searchFocus.pending else { return }
        searchFocus.pending = false
        // Defer so the search field exists when focus is assigned, whether the
        // view was already visible or is appearing for the first time.
        DispatchQueue.main.async { searchKeyFocused = true }
    }

    func buildPickView(for keys: [String], @ViewBuilder label: () -> some View) -> some View {
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
        searchError = nil
        logger.info("search: term=\(searchKey) region=\(searchRegion) type=\(searchType.rawValue)")
        Task {
            do {
                var result = try await ApplePackage.Searcher.search(
                    term: searchKey,
                    countryCode: searchRegion,
                    limit: 32,
                    entityType: searchType,
                )
                if let app = try? await ApplePackage.Lookup.lookup(
                    bundleID: searchKey,
                    countryCode: searchRegion,
                ) {
                    result.insert(app, at: 0)
                }
                logger.info("search completed: \(result.count) results for term=\(searchKey)")
                await MainActor.run {
                    searching = false
                    searchResult = result.map { AppStore.AppPackage(software: $0) }
                    searchError = nil
                }
            } catch {
                logger.error("search failed: term=\(searchKey) error=\(error.localizedDescription)")
                await MainActor.run {
                    searching = false
                    searchResult = []
                    searchError = error.localizedDescription
                }
            }
        }
    }
}

struct ProductDestination: Hashable {
    let archive: AppStore.AppPackage
    let region: String
}

extension SearchView {
    var legacyContent: some View {
        content
            .searchable(text: $searchKey, prompt: "Keyword") {}
            #if os(macOS)
                .searchFocused($searchKeyFocused)
            #endif
            .onSubmit(of: .search) { search() }
            .navigationTitle("Search - \(searchRegion.uppercased())")
            .toolbar { tools }
    }
}

// MARK: - Liquid Glass

#if os(iOS)
    @available(iOS 26.0, *)
    extension SearchView {
        var modernContent: some View {
            content
                .searchable(text: $searchKey, placement: searchablePlacement, prompt: "Keyword")
                .onSubmit(of: .search) { search() }
                .toolbarVisibility(navigationBarVisibility, for: .navigationBar)
                .navigationTitle(Text("Search - \(searchRegion.uppercased())"))
                .toolbar {
                    if navigationBarVisibility != .hidden {
                        tools
                    }
                }
                .safeAreaBar(edge: .top) {
                    if navigationBarVisibility == .hidden {
                        HStack {
                            Menu {
                                searchTypePicker
                            } label: {
                                Label(searchType.rawValue, systemImage: searchType.iconName)
                            }
                            .buttonStyle(.glass)

                            Spacer()

                            searchRegionView()
                                .buttonStyle(.glass)
                        }
                        .padding([.bottom, .horizontal])
                    }
                }
                .animation(.spring, value: searchResult)
                .animation(.spring, value: searching)
        }

        var navigationBarVisibility: Visibility {
            switch horizontalSizeClass {
            case .compact:
                .hidden
            default:
                .automatic
            }
        }

        var searchablePlacement: SearchFieldPlacement {
            switch horizontalSizeClass {
            case .compact:
                .automatic
            default:
                .toolbar
            }
        }
    }
#endif

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
        case .appleTV:
            "appletv"
        }
    }
}
