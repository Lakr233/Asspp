//
//  ProductVersionView.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import SwiftUI

struct ProductVersionView: View {
    let accountID: String
    let package: AppStore.AppPackage
    @StateObject var dvm = Downloads.this
    @State var obtainDownloadURL: Bool = false
    @State var showDownloadPage = false
    @State var hint: String = ""
    @State var hintColor: Color?
    var body: some View {
        if let req = dvm.downloadRequest(forArchive: package) {
            NavigationLink(destination: PackageView(pkg: req), isActive: $showDownloadPage) {
                HStack {
                    Text(package.software.version)
                    Spacer()
                    Text("Show Download")
                }
            }
        } else {
            Button {
                startDownload()
            } label: {
                VStack(alignment: .leading) {
                    if obtainDownloadURL {
                        Text("Communicating with Apple...")
                    } else {
                        HStack {
                            Text(package.software.version)
                            Spacer()
                            Text("Request Download")
                        }
                    }

                    if !hint.isEmpty {
                        Text(hint)
                            .foregroundColor(hintColor)
                    }
                }
            }
            .disabled(obtainDownloadURL)
        }
    }

    func startDownload() {
        obtainDownloadURL = true
        Task {
            do {
                try await AppStore.this.withAccount(id: accountID) { account in
                    let downloadOutput = try await ApplePackage.Download.download(
                        account: &account.account,
                        app: package.software,
                        externalVersionID: package.externalVersionID ?? ""
                    )
                    let request = Downloads.this.add(request: .init(
                        account: account,
                        package: package,
                        downloadOutput: downloadOutput
                    ))
                    Downloads.this.resume(request: request)
                }

                await MainActor.run {
                    obtainDownloadURL = false
                    hint = String(localized: "Download Requested")
                    hintColor = nil
                    showDownloadPage = true
                }
            } catch {
                DispatchQueue.main.async {
                    obtainDownloadURL = false
                    hint = String(localized: "Unable to retrieve download url, please try again later.") + "\n" + error.localizedDescription
                    hintColor = .red
                }
            }
        }
    }
}
