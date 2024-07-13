//
//  iTunesResponse.swift
//  IPATool
//
//  Created by Majd Alfhaily on 22.05.21.
//

import Foundation

public struct iTunesResponse {
    let results: [iTunesArchive]
    let count: Int
}

public extension iTunesResponse {
    struct iTunesArchive: Identifiable, Equatable, Hashable {
        public var id: String { bundleIdentifier }

        public let bundleIdentifier: String
        public let version: String
        public let identifier: Int
        public let name: String
        public let artworkUrl512: String?
        public let fileSizeBytes: String?

        public let isGameCenterEnabled: Bool?
        public let screenshotUrls: [String]?
        public let currency: String?
        public let artistName: String?
        public let price: Double?
        public let formattedPrice: String?
        public let description: String?
        public let releaseNotes: String?
        public let supportedDevices: [String]?

        public var entityType: EntityType?

        public var byteCountDescription: String {
            guard let fileSizeBytes, let bytes = Int64(fileSizeBytes) else {
                return NSLocalizedString("Unknown", comment: "")
            }
            let fmt = ByteCountFormatter()
            fmt.countStyle = .file
            return fmt.string(fromByteCount: bytes)
        }
    }
}

extension iTunesResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case count = "resultCount"
        case results
    }
}

extension iTunesResponse.iTunesArchive: Codable {
    enum CodingKeys: String, CodingKey {
        case identifier = "trackId"
        case name = "trackName"
        case bundleIdentifier = "bundleId"
        case version
        case artworkUrl512
        case fileSizeBytes
        case isGameCenterEnabled
        case screenshotUrls
        case currency
        case artistName
        case price
        case formattedPrice
        case description
        case releaseNotes
        case supportedDevices
    }
}
