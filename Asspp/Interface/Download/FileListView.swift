//
//  FileListView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/19.
//

import SwiftUI
import ZIPFoundation

struct FileListView: View {
    let packageURL: URL
    let prefix: URL

    init(packageURL: URL, prefix: URL = .init(fileURLWithPath: "/")) {
        self.packageURL = packageURL
        self.prefix = prefix
    }

    @State var items: [Entry] = []
    @State var message = ""
    @State var searchText = ""

    /// Parent path + lowercased file name precomputed once per entry, so
    /// filtering on each keystroke is plain string comparison rather than three
    /// URL allocations per entry.
    private struct IndexedEntry {
        let parent: String
        let name: String
        let entry: Entry
    }

    @State private var indexed: [IndexedEntry] = []

    private func buildIndex(from entries: [Entry]) -> [IndexedEntry] {
        entries.map { entry in
            var path = entry.path
            if !path.hasPrefix("/") {
                path = "/" + path
            }
            let url = URL(fileURLWithPath: path)
            return IndexedEntry(
                parent: url.deletingLastPathComponent().path,
                name: url.lastPathComponent.lowercased(),
                entry: entry,
            )
        }
    }

    var interfaceItems: [Entry] {
        let search = searchText.lowercased()
        return indexed.compactMap { row in
            guard row.parent == prefix.path else { return nil }
            guard search.isEmpty || row.name.contains(search) else { return nil }
            return row.entry
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(interfaceItems, id: \.path) { item in
                    switch item.type {
                    case .directory:
                        NavigationLink(URL(fileURLWithPath: item.path).lastPathComponent) {
                            FileListView(packageURL: packageURL, prefix: URL(fileURLWithPath: item.path))
                        }
                    case .file:
                        NavigationLink(URL(fileURLWithPath: item.path).lastPathComponent) {
                            FileAnalysisView(packageURL: packageURL, relativePath: item.path)
                        }
                    case .symlink:
                        Label(item.path, systemImage: "link")
                    }
                }
                .font(.system(.footnote, design: .monospaced))
            } header: {
                Text(String(format: "Content - %@", prefix.path))
            } footer: {
                if message.isEmpty {
                    Text(String(format: "%d items", items.count))
                } else {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        #else
            .searchable(text: $searchText)
        #endif
            .animation(.spring, value: items)
            .onAppear {
                Task {
                    await MainActor.run {
                        message = "Examining contents..."
                    }
                    do { try await loadContents() }
                    catch {
                        await MainActor.run { message = error.localizedDescription }
                    }
                }
            }
            .navigationTitle("Contents")
    }

    func loadContents() async throws {
        let archive = try Archive(url: packageURL, accessMode: .read)
        // list all files
        var buildList = [Entry]()
        let files = archive.makeIterator()
        while let file = files.next() {
            buildList.append(file)
        }
        let index = buildIndex(from: buildList)
        await MainActor.run {
            items = buildList
            indexed = index
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run {
            message = ""
        }
    }
}
