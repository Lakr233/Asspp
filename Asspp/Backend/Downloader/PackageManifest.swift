//
//  PackageManifest.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import ApplePackage
import Foundation

private let packagesDir = {
    let ret = documentsDirectory.appendingPathComponent("Packages")
    try? FileManager.default.createDirectory(at: ret, withIntermediateDirectories: true)
    return ret
}()

@Observable
class PackageManifest: Identifiable, Codable, Hashable, Equatable {
    @ObservationIgnored private(set) var id: UUID = .init()

    @ObservationIgnored private(set) var account: AppStore.UserAccount
    @ObservationIgnored private(set) var package: AppStore.AppPackage

    @ObservationIgnored private(set) var url: URL
    @ObservationIgnored private(set) var signatures: [ApplePackage.Sinf]
    @ObservationIgnored private(set) var iTunesMetadata: Data

    @ObservationIgnored private(set) var creation: Date

    var state: PackageState = .init()

    var targetLocation: URL {
        packagesDir
            .appendingPathComponent(package.software.bundleID)
            .appendingPathComponent(package.software.version)
            .appendingPathComponent("\(id.uuidString)")
            .appendingPathExtension("ipa")
    }

    var completed: Bool {
        state.status == .completed
    }

    func waitForCompletion(timeout: TimeInterval? = nil) async {
        let start = Date().timeIntervalSince1970
        while true {
            if let timeout, Date().timeIntervalSince1970 - start > timeout {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(5e8))
            // .paused is terminal for waiters: a user-paused download will not
            // progress on its own, so the update flow must not spin forever.
            if [.failed, .completed, .paused].contains(state.status) {
                return
            }
        }
    }

    init(account: AppStore.UserAccount, package: AppStore.AppPackage, downloadOutput: ApplePackage.DownloadOutput) throws {
        self.account = account
        self.package = package
        guard let url = URL(string: downloadOutput.downloadURL) else {
            throw NSError(
                domain: "Asspp.Download",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid download URL: \(downloadOutput.downloadURL)"],
            )
        }
        self.url = url
        signatures = downloadOutput.sinfs
        iTunesMetadata = downloadOutput.iTunesMetadata
        creation = .init()
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        account = try container.decode(AppStore.UserAccount.self, forKey: .account)
        package = try container.decode(AppStore.AppPackage.self, forKey: .package)
        url = try container.decode(URL.self, forKey: .url)
        signatures = try container.decode([ApplePackage.Sinf].self, forKey: .signatures)
        iTunesMetadata = try container.decodeIfPresent(Data.self, forKey: .iTunesMetadata) ?? Data()
        creation = try container.decode(Date.self, forKey: .creation)
        state = try container.decode(PackageState.self, forKey: .runtime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(account, forKey: .account)
        try container.encode(package, forKey: .package)
        try container.encode(url, forKey: .url)
        try container.encode(signatures, forKey: .signatures)
        try container.encode(iTunesMetadata, forKey: .iTunesMetadata)
        try container.encode(creation, forKey: .creation)
        try container.encode(state, forKey: .runtime)
    }

    private enum CodingKeys: String, CodingKey {
        case id, account, package, url, signatures, iTunesMetadata, creation, runtime
    }

    /// Identity is the immutable UUID; hashing mutable fields like `state` would
    /// change a manifest's hash mid-download and break Set/Dictionary lookups.
    static func == (lhs: PackageManifest, rhs: PackageManifest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension PackageManifest {
    func delete() {
        try? FileManager.default.removeItem(at: targetLocation)
        var cleanUpDir = targetLocation.deletingLastPathComponent()
        do {
            while FileManager.default.fileExists(atPath: cleanUpDir.path),
                  try FileManager.default.contentsOfDirectory(atPath: cleanUpDir.path).isEmpty,
                  cleanUpDir.path != packagesDir.path,
                  cleanUpDir.path.count > packagesDir.path.count,
                  cleanUpDir.path.contains(packagesDir.path)
            {
                try? FileManager.default.removeItem(at: cleanUpDir)
                cleanUpDir.deleteLastPathComponent()
            }
        } catch {}
    }
}
