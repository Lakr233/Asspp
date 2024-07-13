//
//  AddDownloadView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import ApplePackage
import SwiftUI

struct AddDownloadView: View {
    @State var bundleID: String = ""
    @State var searchType: EntityType = .iPhone
    @State var selection: AppStore.Account.ID = .init()
    @State var obtainDownloadURL = false
    @State var hint = ""

    @FocusState var searchKeyFocused

    @StateObject var avm = AppStore.this
    @StateObject var dvm = Downloads.this

    @Environment(\.dismiss) var dismiss

    var account: AppStore.Account? {
        avm.accounts.first { $0.id == selection }
    }

    var body: some View {
        List {
            Section {
                TextField("Bundle ID", text: $bundleID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.none)
                    .focused($searchKeyFocused)
                    .onSubmit { startDownload() }
                Picker("EntityType", selection: $searchType) {
                    ForEach(EntityType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Bundle ID")
            } footer: {
                Text("Tell us the bundle ID of the app to initial a direct download. Useful to download apps that are no longer available in App Store.")
            }

            Section {
                if avm.demoMode {
                    Text("Demo Mode Redacted")
                        .redacted(reason: .placeholder)
                } else {
                    Picker("Account", selection: $selection) {
                        ForEach(avm.accounts) { account in
                            Text(account.email)
                                .id(account.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onAppear { selection = avm.accounts.first?.id ?? .init() }
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Select an account to download this app")
            }

            Section {
                Button(obtainDownloadURL ? "Communicating with Apple..." : "Request Download") {
                    startDownload()
                }
                .disabled(bundleID.isEmpty)
                .disabled(obtainDownloadURL)
                .disabled(account == nil)
            } footer: {
                if hint.isEmpty {
                    Text("Package can be installed later in download page.")
                } else {
                    Text(hint)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Direct Download")
    }

    func startDownload() {
        guard let account else { return }
        searchKeyFocused = false
        obtainDownloadURL = true
        DispatchQueue.global().async {
            let httpClient = HTTPClient(urlSession: URLSession.shared)
            let itunesClient = iTunesClient(httpClient: httpClient)
            let storeClient = StoreClient(httpClient: httpClient)

            do {
                let app = try itunesClient.lookup(
                    type: searchType,
                    bundleIdentifier: bundleID,
                    region: account.countryCode
                )
                let item = try storeClient.item(
                    identifier: String(app.identifier),
                    directoryServicesIdentifier: account.storeResponse.directoryServicesIdentifier
                )
                let id = Downloads.this.add(request: .init(
                    account: account,
                    package: app,
                    item: item
                ))
                Downloads.this.resume(requestID: id)
            } catch {
                DispatchQueue.main.async {
                    obtainDownloadURL = false
                    if (error as NSError).code == 9610 {
                        hint = NSLocalizedString("License Not Found, please acquire license first.", comment: "")
                    } else if (error as NSError).code == 2034 {
                        hint = NSLocalizedString("Password Token Expired, please re-authenticate within account page.", comment: "")
                    } else if (error as NSError).code == 2059 {
                        hint = NSLocalizedString("Temporarily Unavailable, please try again later.", comment: "")
                    } else {
                        hint = NSLocalizedString("Unable to retrieve download url, please try again later.", comment: "") + "\n" + error.localizedDescription
                    }
                }
                return
            }
            DispatchQueue.main.async {
                hint = NSLocalizedString("Download Requested", comment: "")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismiss()
            }
        }
    }
}
