//
//  Downloads+UI.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import ApplePackage
import Foundation
import SwiftUI

enum DownloadAction: Hashable {
    case suspend
    case resume
    case restart
    case delete
}

@MainActor
extension Downloads {
    func performDownloadAction(for request: PackageManifest, action: DownloadAction) {
        switch action {
        case .suspend:
            suspend(request: request)
        case .resume:
            resume(request: request)
        case .restart:
            restart(request: request)
        case .delete:
            delete(request: request)
        }
    }

    func getAvailableActions(for request: PackageManifest) -> [DownloadAction] {
        switch request.state.status {
        case .pending, .downloading:
            [.suspend, .delete]
        case .paused:
            [.resume, .delete]
        case .failed:
            [.restart, .delete]
        case .completed:
            [.delete]
        }
    }

    func getActionLabel(for action: DownloadAction) -> (title: String, systemImage: String, isDestructive: Bool) {
        switch action {
        case .suspend:
            (String(localized: "Pause"), "stop.fill", false)
        case .resume:
            (String(localized: "Resume"), "play.fill", false)
        case .restart:
            (String(localized: "Restart Download"), "arrow.clockwise", false)
        case .delete:
            (String(localized: "Delete"), "trash", true)
        }
    }
}

extension Downloads {
    func startDownload(for package: AppStore.AppPackage, accountID: String) async throws {
        try await AppStore.this.withAccount(id: accountID) { account in
            let externalVersionID = try await resolveExternalVersionID(for: package, account: account.account)
            let downloadOutput = try await ApplePackage.Download.download(
                account: &account.account,
                app: package.software,
                externalVersionID: externalVersionID,
            )
            let request = try Downloads.this.add(request: .init(
                account: account,
                package: package,
                downloadOutput: downloadOutput,
            ))
            Downloads.this.resume(request: request)
        }
    }

    private func resolveExternalVersionID(for package: AppStore.AppPackage, account: ApplePackage.Account) async throws -> String {
        if let externalVersionID = package.externalVersionID, !externalVersionID.isEmpty {
            return externalVersionID
        }
        guard let entityType = package.entityType,
              let countryCode = ApplePackage.Configuration.countryCode(for: account.store)
        else {
            return ""
        }
        let metadata = try await ApplePackage.PlatformVersionLookup.lookup(
            appID: package.software.id,
            countryCode: countryCode,
            entityType: entityType
        )
        return metadata.externalVersionID
    }
}
