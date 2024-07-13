//
//  StoreEndpoint.swift
//  IPATool
//
//  Created by Majd Alfhaily on 22.05.21.
//

import Foundation

enum StoreEndpoint {
    case authenticate(prefix: String, guid: String)
    case download(guid: String)
    case buy
}

extension StoreEndpoint: HTTPEndpoint {
    var url: URL {
        var components = URLComponents(string: path)!
        components.scheme = "https"
        components.host = host
        return components.url!
    }

    private var host: String {
        switch self {
        case let .authenticate(prefix, _):
            "\(prefix)-buy.itunes.apple.com"
        case .buy:
            "buy.itunes.apple.com"
        case .download:
            "p25-buy.itunes.apple.com"
        }
    }

    private var path: String {
        switch self {
        case let .authenticate(_, guid):
            "/WebObjects/MZFinance.woa/wa/authenticate?guid=\(guid)"
        case .buy:
            "/WebObjects/MZBuy.woa/wa/buyProduct"
        case let .download(guid):
            "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(guid)"
        }
    }
}
