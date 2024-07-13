//
//  AccountDetailView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI

struct AccountDetailView: View {
    let account: AppStore.Account

    @StateObject var vm = AppStore.this
    @Environment(\.dismiss) var dismiss

    @State var rotating = false
    @State var rotatingHint = ""

    var body: some View {
        List {
            Section {
                if vm.demoMode {
                    Text("88888888888")
                        .redacted(reason: .placeholder)
                } else {
                    Text(account.email)
                        .onTapGesture { UIPasteboard.general.string = account.email }
                }
            } header: {
                Text("ID")
            } footer: {
                Text("This email is used to sign in to Apple services.")
            }
            Section {
                Text("\(account.countryCode) - \(ApplePackage.countryCodeMap[account.countryCode] ?? NSLocalizedString("Unknown", comment: ""))")
                    .onTapGesture { UIPasteboard.general.string = account.email }
            } header: {
                Text("Country Code")
            } footer: {
                Text("App Store requires this country code to identify your package region.")
            }
            Section {
                if vm.demoMode {
                    Text("88888888888")
                        .redacted(reason: .placeholder)
                } else {
                    Text(account.storeResponse.directoryServicesIdentifier)
                        .font(.system(.body, design: .monospaced))
                        .onTapGesture { UIPasteboard.general.string = account.email }
                }
                Text(ApplePackage.overrideGUID ?? "Seed Not Available")
                    .font(.system(.body, design: .monospaced))
                    .onTapGesture { UIPasteboard.general.string = account.email }
            } header: {
                Text("Services ID")
            } footer: {
                Text("ID combined with a random seed generated on this device can download package from App Store.")
            }
            Section {
                SecureField(text: .constant(account.storeResponse.passwordToken)) {
                    Text("Password Token")
                }
                if rotating {
                    Button("Rotating...") {}
                        .disabled(true)
                } else {
                    Button("Rotate Token") { rotate() }
                }
            } header: {
                Text("Password Token")
            } footer: {
                if rotatingHint.isEmpty {
                    Text("If you failed to acquire license for product, rotate the password token may help. This will use the initial password to authenticate with App Store again.")
                } else {
                    Text(rotatingHint)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button("Delete") {
                    vm.delete(id: account.id)
                    dismiss()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Detail")
    }

    func rotate() {
        rotating = true
        DispatchQueue.global().async {
            do {
                try vm.rotate(id: account.id)
                DispatchQueue.main.async {
                    rotating = false
                    rotatingHint = NSLocalizedString("Success", comment: "")
                }
            } catch {
                DispatchQueue.main.async {
                    rotating = false
                    rotatingHint = error.localizedDescription
                }
            }
        }
    }
}
