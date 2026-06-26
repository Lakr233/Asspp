//
//  AppPackageArchive.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import Foundation
import OrderedCollections

@MainActor
@Observable
class AppPackageArchive {
    @ObservationIgnored
    let accountIdentifier: String?
    @ObservationIgnored
    let region: String

    var package: AppStore.AppPackage

    typealias VersionIdentifier = String
    @ObservationIgnored
    private var _versionIdentifiers: Persist<[VersionIdentifier]>

    var versionIdentifiers: [VersionIdentifier] {
        get {
            access(keyPath: \.versionIdentifiers)
            return _versionIdentifiers.wrappedValue
        }
        set {
            withMutation(keyPath: \.versionIdentifiers) {
                _versionIdentifiers.wrappedValue = newValue
            }
        }
    }

    @ObservationIgnored
    private var _versionItems: Persist<OrderedDictionary<VersionIdentifier, VersionMetadata>>

    var versionItems: OrderedDictionary<VersionIdentifier, VersionMetadata> {
        get {
            access(keyPath: \.versionItems)
            return _versionItems.wrappedValue
        }
        set {
            withMutation(keyPath: \.versionItems) {
                _versionItems.wrappedValue = newValue
            }
        }
    }

    var isVersionItemsFullyLoaded: Bool {
        assert(versionItems.count <= versionIdentifiers.count)
        return versionItems.count == versionIdentifiers.count
    }

    var error: String?
    var loading = false
    var shouldDismiss = false

    init(accountID: String?, region: String, package: AppStore.AppPackage) {
        accountIdentifier = accountID
        self.region = region
        self.package = package

        let packageIdentifier = [
            package.id,
            package.software.bundleID.lowercased(),
            region,
            package.entityType?.rawValue ?? "unknown",
        ]
            .joined()
            .lowercased()
        _versionItems = Persist(key: "\(packageIdentifier).versions", defaultValue: [:])
        _versionIdentifiers = Persist(key: "\(packageIdentifier).versionNumbers", defaultValue: [])
    }

    func package(for externalVersion: String) -> AppStore.AppPackage? {
        if let metadata = versionItems[externalVersion] {
            var pkg = package
            pkg.software.version = metadata.displayVersion
            pkg.externalVersionID = externalVersion
            return pkg
        } else {
            return nil
        }
    }

    func clearVersionItems() {
        assert(!loading)
        error = nil
        versionIdentifiers = []
        versionItems = [:]
    }

    func populateVersionIdentifiers(_ completion: (() async -> Void)? = nil) {
        guard let accountIdentifier, !loading else { return }
        let bundleID = package.software.bundleID
        loading = true
        error = nil

        Task {
            do {
                let versions = try await AppStore.this.withAccount(id: accountIdentifier) { userAccount in
                    try await VersionFinder.list(
                        account: &userAccount.account,
                        bundleIdentifier: bundleID,
                        entityType: self.package.entityType
                    )
                }
                self.versionIdentifiers = versions.reversed()
            } catch {
                if case .licenseRequired = error as? ApplePackageError {
                    self.shouldDismiss = true
                }
                self.error = error.localizedDescription
            }
            self.loading = false
            await completion?()
        }
    }

    func populateNextVersionItems(count: Int = 3) {
        guard let accountIdentifier, !loading, !isVersionItemsFullyLoaded else { return }
        loading = true
        error = nil

        Task {
            do {
                for _ in 0 ..< count where !self.isVersionItemsFullyLoaded {
                    let nextIdx = self.versionItems.count
                    let version = self.versionIdentifiers[nextIdx]
                    let app = self.package.software

                    let metadata = try await AppStore.this.withAccount(id: accountIdentifier) { userAccount in
                        try await VersionLookup.getVersionMetadata(account: &userAccount.account, app: app, versionID: version)
                    }
                    self.versionItems[version] = metadata
                }
            } catch {
                self.error = error.localizedDescription
            }
            self.loading = false
        }
    }

    func populateVersionItem(for versionID: String) {
        guard let accountIdentifier, !loading, versionIdentifiers.contains(versionID), versionItems[versionID] == nil else { return }
        loading = true
        error = nil

        Task {
            do {
                let app = self.package.software
                let metadata = try await AppStore.this.withAccount(id: accountIdentifier) { userAccount in
                    try await VersionLookup.getVersionMetadata(account: &userAccount.account, app: app, versionID: versionID)
                }
                self.versionItems[versionID] = metadata
            } catch {
                self.error = error.localizedDescription
            }
            self.loading = false
        }
    }
}

extension AppPackageArchive {
    var version: String {
        package.software.version
    }

    var releaseDate: Date? {
        package.releaseDate
    }

    var releaseNotes: String? {
        package.software.releaseNotes
    }

    var formattedPrice: String? {
        package.software.formattedPrice
    }

    var price: Double? {
        package.software.price
    }

    var downloadOutput: DownloadOutput? {
        get { package.downloadOutput }
        set { package.downloadOutput = newValue }
    }
}
