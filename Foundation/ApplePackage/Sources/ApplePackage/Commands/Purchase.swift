//
//  Purchase.swift
//
//
//  Created by 秋星桥 on 2024/7/12.
//

import Foundation

public extension ApplePackage {
    static func purchase(token: String, directoryServicesIdentifier: String, trackID: Int, countryCode: String) throws {
        let httpClient = HTTPClient(urlSession: URLSession.shared)
        let storeClient = StoreClient(httpClient: httpClient)
        try storeClient.buy(token: token, directoryServicesIdentifier: directoryServicesIdentifier, trackID: trackID, countryCode: countryCode)
    }
}
