//
//  ProductView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct ProductView: View {
    let archive: iTunesResponse.iTunesArchive
    let region: String

    @StateObject var vm = AppStore.this
    @StateObject var dvm = Downloads.this

    var eligibleAccounts: [AppStore.Account] {
        vm.accounts.filter { $0.countryCode == region }
    }

    var account: AppStore.Account? {
        vm.accounts.first { $0.id == selection }
    }

    @State var selection: AppStore.Account.ID = .init()
    @State var obtainDownloadURL = false
    @State var hint: String = ""
    @State var licenseHint: String = ""
    @State var acquiringLicense = false

    var body: some View {
        List {
            packageHeader
            if account == nil {
                Section {
                    Text("No account available for this region.")
                        .foregroundStyle(.red)
                } header: {
                    Text("Error")
                } footer: {
                    Text("Please add account in account page.")
                }
            }
            pricing
            accountSelector
            buttons
            descriptionField
        }
        .onAppear {
            selection = eligibleAccounts.first?.id ?? .init()
        }
        .navigationTitle("Select Account")
    }

    var packageHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                KFImage(URL(string: archive.artworkUrl512 ?? ""))
                    .antialiased(true)
                    .resizable()
                    .cornerRadius(8)
                    .frame(width: 50, height: 50, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(archive.name)
                    .bold()
                if let realaseNote = archive.releaseNotes {
                    Text(realaseNote)
                        .font(.system(.footnote, design: .rounded))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Package")
        } footer: {
            Label("\(archive.bundleIdentifier) - \(archive.version) - \(archive.byteCountDescription)", systemImage: archive.displaySupportedDevicesIcon)
        }
    }

    var pricing: some View {
        Section {
            Text("\(archive.formattedPrice ?? NSLocalizedString("Unknown", comment: ""))")
                .font(.system(.body, design: .rounded))
            if let price = archive.price, price.isZero {
                Button("Acquire License") {
                    acquireLicense()
                }
                .disabled(acquiringLicense)
                .disabled(account == nil)
            }
        } header: {
            Text("Pricing - \(archive.currency ?? "?")")
        } footer: {
            if licenseHint.isEmpty {
                Text("Acquire license is not available for paid apps. If so, make purchase from the real App Store before download from here. If you already purchased this app, this operation will fail.")
            } else {
                Text(licenseHint)
                    .foregroundStyle(.red)
            }
        }
    }

    var accountSelector: some View {
        Section {
            if vm.demoMode {
                Text("Demo Mode Redacted")
                    .redacted(reason: .placeholder)
            } else {
                Picker("Account", selection: $selection) {
                    ForEach(eligibleAccounts) { account in
                        Text(account.email)
                            .id(account.id)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("You have searched this package with region \(region)")
        }
    }

    var buttons: some View {
        Section {
            if let req = dvm.downloadRequest(forArchive: archive) {
                NavigationLink(destination: PackageView(request: req)) {
                    Text("Show Download")
                }
            } else {
                Button(obtainDownloadURL ? "Communicating with Apple..." : "Request Download") {
                    startDownload()
                }
                .disabled(obtainDownloadURL)
                .disabled(account == nil)
            }
        } header: {
            Text("Download")
        } footer: {
            if hint.isEmpty {
                Text("Package can be installed later in download page.")
            } else {
                Text(hint)
                    .foregroundStyle(.red)
            }
        }
    }

    var descriptionField: some View {
        Section {
            Text(archive.description ?? "No description provided")
                .font(.system(.footnote, design: .rounded))
        } header: {
            Text("Description")
        }
    }

    func startDownload() {
        guard let account else { return }
        obtainDownloadURL = true
        DispatchQueue.global().async {
            let httpClient = HTTPClient(urlSession: URLSession.shared)
            let itunesClient = iTunesClient(httpClient: httpClient)
            let storeClient = StoreClient(httpClient: httpClient)

            do {
                let app = try itunesClient.lookup(
                    type: archive.entityType ?? .iPhone,
                    bundleIdentifier: archive.bundleIdentifier,
                    region: account.countryCode
                )
                let item = try storeClient.item(
                    identifier: String(app.identifier),
                    directoryServicesIdentifier: account.storeResponse.directoryServicesIdentifier
                )
                let id = Downloads.this.add(request: .init(
                    account: account,
                    package: archive,
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
                obtainDownloadURL = false
                hint = NSLocalizedString("Download Requested", comment: "")
            }
        }
    }

    func acquireLicense() {
        guard let account else { return }
        acquiringLicense = true
        DispatchQueue.global().async {
            do {
                guard let account = try AppStore.this.rotate(id: account.id) else {
                    throw NSError(domain: "AppStore", code: 401, userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString(
                            "Failed to rotate password token, please re-authenticate within account page.",
                            comment: ""
                        ),
                    ])
                }
                try ApplePackage.purchase(
                    token: account.storeResponse.passwordToken,
                    directoryServicesIdentifier: account.storeResponse.directoryServicesIdentifier,
                    trackID: archive.identifier,
                    countryCode: account.countryCode
                )
                DispatchQueue.main.async {
                    acquiringLicense = false
                    licenseHint = NSLocalizedString("Request Successes", comment: "")
                }
            } catch {
                DispatchQueue.main.async {
                    acquiringLicense = false
                    licenseHint = error.localizedDescription
                }
            }
        }
    }
}

extension iTunesResponse.iTunesArchive {
    var displaySupportedDevicesIcon: String {
        var supports_iPhone = false
        var supports_iPad = false
        for device in supportedDevices ?? [] {
            if device.lowercased().contains("iphone") {
                supports_iPhone = true
            }
            if device.lowercased().contains("ipad") {
                supports_iPad = true
            }
        }
        if supports_iPhone, supports_iPad {
            return "ipad.and.iphone"
        } else if supports_iPhone {
            return "iphone"
        } else if supports_iPad {
            return "ipad"
        } else {
            return "questionmark"
        }
    }
}
