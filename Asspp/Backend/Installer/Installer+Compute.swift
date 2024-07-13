//
//  Installer+Compute.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Foundation

extension Installer {
    var plistEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/\(id).plist"
        comps.port = port
        return comps.url!
    }

    var payloadEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/\(id).ipa"
        comps.port = port
        return comps.url!
    }

    var iTunesLink: URL {
        var comps = URLComponents()
        comps.scheme = "itms-services"
        comps.path = "/"
        comps.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: plistEndpoint.absoluteString),
        ]
        comps.port = port
        return comps.url!
    }

    var displayImageSmallEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/app57x57.png"
        comps.port = port
        return comps.url!
    }

    var displayImageSmallData: Data {
        createWhite(57)
    }

    var displayImageLargeEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/app512x512.png"
        comps.port = port
        return comps.url!
    }

    var displayImageLargeData: Data {
        createWhite(512)
    }

    var indexHtml: String {
        """
        <html> <head> <meta http-equiv="refresh" content="0;url=\(iTunesLink.absoluteString)"> </head> </html>
        """
    }

    var installManifest: [String: Any] {
        [
            "items": [
                [
                    "assets": [
                        [
                            "kind": "software-package",
                            "url": payloadEndpoint.absoluteString,
                        ],
                        [
                            "kind": "display-image",
                            "url": displayImageSmallEndpoint.absoluteString,
                        ],
                        [
                            "kind": "full-size-image",
                            "url": displayImageLargeEndpoint.absoluteString,
                        ],
                    ],
                    "metadata": [
                        "bundle-identifier": archive.bundleIdentifier,
                        "bundle-version": archive.version,
                        "kind": "software",
                        "title": archive.name,
                    ],
                ],
            ],
        ]
    }

    var installManifestData: Data {
        (try? PropertyListSerialization.data(
            fromPropertyList: installManifest,
            format: .xml,
            options: .zero
        )) ?? .init()
    }
}
