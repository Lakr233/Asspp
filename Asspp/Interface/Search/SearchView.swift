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
    let regionKeys = Array(ApplePackage.countryCodeMap.keys.sorted())

    @State var searchInput: String = ""
    @State var searchResult: [iTunesResponse.iTunesArchive] = []

    @StateObject var vm = AppStore.this

    var possibleReigon: Set<String> {
        Set(vm.accounts.map(\.countryCode))
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Search")
        }
        .navigationViewStyle(.stack)
    }

    var content: some View {
        List {
            Section {
                Picker("Type", selection: $searchType) {
                    ForEach(EntityType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)

                buildRegionView()

                TextField("Keyword", text: $searchKey)
                    .focused($searchKeyFocused)
                    .onSubmit { search() }
            } header: {
                Text("Metadata")
            }
            Section {
                Button(searching ? "Searching..." : "Search") { search() }
                    .disabled(searchKey.isEmpty)
                    .disabled(searching)
            }
            Section {
                ForEach(searchResult) { item in
                    NavigationLink(destination: ProductView(archive: item, region: searchRegion)) {
                        ArchivePreviewView(archive: item)
                    }
                    .transition(.opacity)
                }
            } header: {
                Text(searchInput)
            }
        }
        .animation(.spring, value: searchResult)
    }

    func buildRegionView() -> some View {
        HStack {
            Text("Region")
            Spacer()
            Menu {
                Section("Account") {
                    buildPickView(for: regionKeys.filter { possibleReigon.contains($0) })
                }
                Menu("All Region") {
                    buildPickView(for: regionKeys)
                }
            } label: {
                HStack {
                    Text("\(searchRegion) - \(ApplePackage.countryCodeMap[searchRegion] ?? NSLocalizedString("Unknown", comment: ""))")
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    func buildPickView(for keys: [String]) -> some View {
        ForEach(keys, id: \.self) { key in
            Button("\(key) - \(ApplePackage.countryCodeMap[key] ?? NSLocalizedString("Unknown", comment: ""))") {
                searchRegion = key
            }
        }
    }

    func search() {
        searchKeyFocused = false
        searching = true
        searchInput = "\(searchRegion) - \(searchKey)" + " ..."
        DispatchQueue.global().async {
            var result = (try? ApplePackage.search(
                type: searchType,
                term: searchKey,
                limit: 32,
                region: searchRegion
            )) ?? []

            let httpClient = HTTPClient(urlSession: URLSession.shared)
            let itunesClient = iTunesClient(httpClient: httpClient)
            if let app = try? itunesClient.lookup(
                type: searchType,
                bundleIdentifier: searchKey,
                region: searchRegion
            ) {
                result.insert(app, at: 0)
            }

            DispatchQueue.main.async {
                searching = false
                searchResult = result
                searchInput = "\(searchRegion) - \(searchKey)"
            }
        }
    }
}
