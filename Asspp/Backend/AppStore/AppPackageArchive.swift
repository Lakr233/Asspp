//
//  AppPackageArchive.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import Foundation
import OrderedCollections

class AppPackageArchive: ObservableObject {
    let accountID: String?
    let region: String
    @MainActor @Published var package: AppStore.AppPackage
    @MainActor @PublishedPersist var historyPackages: OrderedDictionary<String, VersionMetadata> {
        didSet {
            isLoadMoreAvailable = versionNumbers.count > historyPackages.count
        }
    }

    @MainActor private var versionNumbers: [String] = [] {
        didSet {
            isLoadMoreAvailable = versionNumbers.count > historyPackages.count
        }
    }

    @MainActor @Published var errorMessage: String?

    @MainActor @Published var isLoadMoreAvailable = false
    @MainActor @Published var isLoadingVersionDetails = false

    init(accountID: String?, region: String, package: AppStore.AppPackage) {
        self.accountID = accountID
        self.region = region
        _package = .init(initialValue: package)
        _historyPackages = .init(key: package.id + ".versions", defaultValue: [:])
    }

    @MainActor
    func package(for externalVersion: String) -> AppStore.AppPackage? {
        if let metadata = historyPackages[externalVersion] {
            var pkg = package
            pkg.software.version = metadata.displayVersion
            pkg.externalVersionID = externalVersion
            return pkg
        } else {
            return nil
        }
    }

    func lookupHistoryVersions() {
        guard let accountID else {
            return
        }
        Task.detached {
            do {
                let bundleID = await self.package.software.bundleID
                let versions = try await AppStore.this.withAccount(id: accountID) { userAccount in
                    try await VersionFinder.list(account: &userAccount.account, bundleIdentifier: bundleID)
                }
                await MainActor.run {
                    self.versionNumbers = versions.reversed()
                }
                if await self.historyPackages.isEmpty {
                    self.loadNextPageIfNeeded()
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func loadNextPageIfNeeded(count: Int = 5) {
        guard let accountID else { return }
        Task.detached {
            guard await self.isLoadMoreAvailable else {
                return
            }

            do {
                await MainActor.run {
                    self.isLoadingVersionDetails = true
                }
                for _ in 0 ..< count {
                    let nextIdx = await self.historyPackages.count
                    guard await self.versionNumbers.indices.contains(nextIdx) else {
                        return
                    }
                    let version = await self.versionNumbers[nextIdx]
                    let app = await self.package.software

                    let metadata = try await AppStore.this.withAccount(id: accountID) { userAccount in
                        try await VersionLookup.getVersionMetadata(account: &userAccount.account, app: app, versionID: version)
                    }
                    await MainActor.run {
                        self.historyPackages[version] = metadata
                    }
                }
                await MainActor.run {
                    self.isLoadingVersionDetails = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingVersionDetails = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

extension AppPackageArchive {
    @MainActor var version: String {
        package.software.version
    }

    @MainActor var releaseDate: Date? {
        package.releaseDate
    }

    @MainActor var releaseNotes: String? {
        package.software.releaseNotes
    }

    @MainActor var formattedPrice: String {
        package.software.formattedPrice
    }

    @MainActor var price: Double? {
        package.software.price
    }

    @MainActor var downloadOutput: DownloadOutput? {
        get { package.downloadOutput }
        set { package.downloadOutput = newValue }
    }
}
