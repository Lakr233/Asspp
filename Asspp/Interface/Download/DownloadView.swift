//
//  DownloadView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct DownloadView: View {
    @State private var vm = Downloads.this

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Downloads")
        }
    }

    private var content: some View {
        Group {
            if vm.manifests.isEmpty {
                ContentUnavailableView(
                    label: {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    },
                    description: {
                        Text("Search for an app or add a download link to get started.")
                    },
                    actions: {
                        NavigationLink("Add Download") {
                            AddDownloadView()
                        }
                    },
                )
                .padding()
            } else {
                Form {
                    packageList
                }
            }
        }
        .formStyle(.grouped)
        .navigationDestination(for: PackageManifest.self) { manifest in
            PackageView(pkg: manifest)
        }
        .toolbar {
            NavigationLink(destination: AddDownloadView()) {
                Image(systemName: "plus")
            }
        }
    }

    private var packageList: some View {
        ForEach(vm.manifests, id: \.id) { req in
            PackageManifestRow(manifest: req)
        }
    }
}

private struct PackageManifestRow: View {
    let manifest: PackageManifest
    @State private var vm = Downloads.this

    var body: some View {
        NavigationLink(value: manifest) {
            VStack(spacing: 8) {
                ArchivePreviewView(archive: manifest.package)
                SimpleProgress(progress: manifest.state.percent)
                    .animation(.interactiveSpring, value: manifest.state.percent)
                HStack {
                    Text(manifest.hint)
                    Spacer()
                    Text(manifest.creation.formatted())
                }
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            let actions = vm.getAvailableActions(for: manifest)
            ForEach(actions, id: \.self) { action in
                let label = vm.getActionLabel(for: action)
                Button(role: label.isDestructive ? .destructive : .none) {
                    vm.performDownloadAction(for: manifest, action: action)
                } label: {
                    Label(label.title, systemImage: label.systemImage)
                }
            }
        }
    }
}

extension PackageManifest {
    var hint: String {
        if let error = state.error {
            return error
        }
        return switch state.status {
        case .pending:
            String(localized: "Pending...")
        case .downloading:
            [
                String(Int(state.percent * 100)) + "%",
                state.speed.isEmpty ? "" : state.speed + "/s",
            ]
            .compactMap(\.self)
            .joined(separator: " ")
        case .paused:
            String(localized: "Paused")
        case .completed:
            String(localized: "Completed")
        case .failed:
            String(localized: "Failed")
        }
    }
}
