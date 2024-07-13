//
//  Search.swift
//  IPATool
//
//  Created by Majd Alfhaily on 22.05.21.
//

import Foundation

public extension ApplePackage {
    static func search(type: EntityType, term: String, limit: Int = 5, region: String) throws -> [iTunesResponse.iTunesArchive] {
        let httpClient = HTTPClient(urlSession: URLSession.shared)
        let itunesClient = iTunesClient(httpClient: httpClient)
        return try itunesClient.search(type: type, term: term, limit: limit, region: region)
    }
}
