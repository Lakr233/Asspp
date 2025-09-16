//
//  Software.swift
//  ApplePackage
//
//  Created by qaq on 2025/9/14.
//

import Foundation

public struct Software: Codable, Equatable, Hashable, Identifiable {
    public var id: Int64
    public var bundleID: String
    public var name: String
    public var version: String
    public var price: Double?
    public var artistName: String
    public var sellerName: String
    public var description: String
    public var averageUserRating: Double
    public var userRatingCount: Int
    public var artworkUrl: String
    public var screenshotUrls: [String]
    public var minimumOsVersion: String
    public var releaseDate: String
    public var releaseNotes: String?
    public var formattedPrice: String
    public var primaryGenreName: String

    private enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case bundleID = "bundleId"
        case name = "trackName"
        case version
        case price
        case artistName
        case sellerName
        case description
        case averageUserRating
        case userRatingCount
        case artworkUrl = "artworkUrl512"
        case screenshotUrls
        case minimumOsVersion
        case releaseDate = "currentVersionReleaseDate"
        case releaseNotes
        case formattedPrice
        case primaryGenreName
    }

    public init(
        id: Int64,
        bundleID: String,
        name: String,
        version: String,
        price: Double? = nil,
        artistName: String,
        sellerName: String,
        description: String,
        averageUserRating: Double,
        userRatingCount: Int,
        artworkUrl: String,
        screenshotUrls: [String],
        minimumOsVersion: String,
        releaseDate: String,
        formattedPrice: String,
        primaryGenreName: String
    ) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.price = price
        self.artistName = artistName
        self.sellerName = sellerName
        self.description = description
        self.averageUserRating = averageUserRating
        self.userRatingCount = userRatingCount
        self.artworkUrl = artworkUrl
        self.screenshotUrls = screenshotUrls
        self.minimumOsVersion = minimumOsVersion
        self.releaseDate = releaseDate
        self.formattedPrice = formattedPrice
        self.primaryGenreName = primaryGenreName
    }
}
