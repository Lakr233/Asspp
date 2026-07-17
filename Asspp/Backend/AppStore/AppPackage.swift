//
//  AppPackage.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Foundation

extension AppStore {
    struct AppPackage: Codable, Identifiable, Hashable {
        var id: String {
            software.bundleID
        }

        var software: ApplePackage.Software
        var releaseDate: Date?
        var downloadOutput: ApplePackage.DownloadOutput?
        var externalVersionID: String?
        var entityType: EntityType?

        init(software: ApplePackage.Software, entityType: EntityType? = nil) {
            self.software = software
            self.entityType = entityType
            releaseDate = ISO8601DateFormatter().date(from: software.releaseDate)
        }

        static func == (lhs: AppPackage, rhs: AppPackage) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}
