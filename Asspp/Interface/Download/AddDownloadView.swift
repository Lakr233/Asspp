//
//  AddDownloadView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import ApplePackage
import ButtonKit
import SwiftUI

struct AddDownloadView: View {
    @State private var bundleID: String = ""
    @State private var searchType: EntityType = .iPhone
    @State private var selection: AppStore.UserAccount.ID = .init()
    @State private var hint = ""
    @State private var hintIsError = false

    @FocusState private var searchKeyFocused

    @State private var avm = AppStore.this
    @State private var dvm = Downloads.this

    @Environment(\.dismiss) private var dismiss

    var account: AppStore.UserAccount? {
        avm.accounts.first { $0.id == selection }
    }

    var body: some View {
        Form {
            Section {
                TextField("Bundle ID", text: $bundleID)
                #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.none)
                #endif
                    .focused($searchKeyFocused)
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
                Text("Tell us the bundle ID of the app to initiate a direct download. Useful to download apps that are no longer available in App Store.")
            }

            Section {
                Picker("Account", selection: $selection) {
                    ForEach(avm.accounts) { account in
                        Text(account.account.email)
                            .id(account.id)
                    }
                }
                .pickerStyle(.menu)
                .onAppear { selection = avm.accounts.first?.id ?? .init() }
                .redacted(reason: .placeholder, isEnabled: avm.demoMode)
            } header: {
                Text("Account")
            } footer: {
                Text("Select an account to download this app")
            }

            Section {
                AsyncButton {
                    guard let account else { return }
                    searchKeyFocused = false
                    do {
                        guard let countryCode = ApplePackage.Configuration.countryCode(for: account.account.store) else { return }
                        let software = try await ApplePackage.Lookup.lookup(bundleID: bundleID, countryCode: countryCode)
                        let appPackage = AppStore.AppPackage(software: software)
                        try await dvm.startDownload(for: appPackage, accountID: account.id)
                        hint = String(localized: "Download Requested")
                        hintIsError = false
                    } catch {
                        hint = error.localizedDescription
                        hintIsError = true
                        throw error
                    }
                } label: {
                    Text("Request Download")
                }
                .disabledWhenLoading()
                .disabled(bundleID.isEmpty)
                .disabled(account == nil)
            } footer: {
                if hint.isEmpty {
                    Text("The package can be installed later from the Downloads page.")
                } else {
                    Text(hint)
                        .foregroundStyle(hintIsError ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Direct Download")
    }
}
