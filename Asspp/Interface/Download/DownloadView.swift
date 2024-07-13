//
//  DownloadView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct DownloadView: View {
    @StateObject var vm = Downloads.this

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Download")
        }
        .navigationViewStyle(.stack)
    }

    var content: some View {
        List {
            if vm.requests.isEmpty {
                Section("Packages") {
                    Text("Sorry, nothing here.")
                }
            } else {
                Section("Packages") {
                    packageList
                }
            }
        }
        .toolbar {
            NavigationLink(destination: AddDownloadView()) {
                Image(systemName: "plus")
            }
        }
    }

    var packageList: some View {
        ForEach(vm.requests) { req in
            NavigationLink(destination: PackageView(request: req)) {
                VStack(spacing: 8) {
                    ArchivePreviewView(archive: req.package)
                    SimpleProgress(progress: req.runtime.progress)
                        .animation(.interactiveSpring, value: req.runtime.progress)
                    HStack {
                        Text(req.hint)
                        Spacer()
                        Text(req.creation.formatted())
                    }
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if vm.isCompleted(for: req) {
                } else {
                    switch req.runtime.status {
                    case .stopped:
                        Button {
                            vm.resume(requestID: req.id)
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                    case .pending, .downloading:
                        Button {
                            vm.suspend(requestID: req.id)
                        } label: {
                            Label("Puase", systemImage: "stop.fill")
                        }
                    default: Group {}
                    }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    vm.delete(request: req)
                } label: {
                    Label("Cancel", systemImage: "trash")
                }
            }
        }
    }
}

extension Downloads.Request {
    var hint: String {
        if let error = runtime.error {
            return error
        }
        return switch runtime.status {
        case .stopped:
            NSLocalizedString("Suspended", comment: "")
        case .pending:
            NSLocalizedString("Pending...", comment: "")
        case .downloading:
            [
                String(Int(runtime.progress.fractionCompleted * 100)) + "%",
                runtime.speed.isEmpty ? "" : runtime.speed + "/s",
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        case .verifying:
            NSLocalizedString("Verifying...", comment: "")
        case .completed:
            NSLocalizedString("Completed", comment: "")
        }
    }
}
