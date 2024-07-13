//
//  Download.swift
//  IPATool
//
//  Created by Majd Alfhaily on 22.05.21.
//

import Foundation

public extension ApplePackage {
    class Downloader {
        public let email: String
        public let region: String
        public let directoryServicesIdentifier: String

        private let httpClient: HTTPClient
        private let itunesClient: iTunesClient
        private let storeClient: StoreClient
        private let downloadClient: HTTPDownloadClient

        public typealias ProgressBlock = (Float) -> Void
        public var onProgress: ProgressBlock?

        public init(email: String, directoryServicesIdentifier: String, region: String) {
            self.email = email
            self.directoryServicesIdentifier = directoryServicesIdentifier
            self.region = region
            httpClient = HTTPClient(urlSession: URLSession.shared)
            itunesClient = iTunesClient(httpClient: httpClient)
            storeClient = StoreClient(httpClient: httpClient)
            downloadClient = HTTPDownloadClient()
        }

        public func download(type: EntityType, bundleIdentifier: String, saveToDirectory: URL, withFileName fileName: String?) throws -> URL {
            let app = try itunesClient.lookup(type: type, bundleIdentifier: bundleIdentifier, region: region)
            let item = try storeClient.item(identifier: String(app.identifier), directoryServicesIdentifier: directoryServicesIdentifier)

            if !FileManager.default.fileExists(atPath: saveToDirectory.path) {
                try FileManager.default.createDirectory(at: saveToDirectory, withIntermediateDirectories: true)
            }
            var isDir = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: saveToDirectory.path, isDirectory: &isDir),
                  isDir.boolValue
            else {
                throw NSError(domain: "ApplePackageDownloader", code: 402, userInfo: ["description": "File permission denied"])
            }

            let name = fileName ?? "\(bundleIdentifier)_\(app.identifier)_v\(app.version).ipa"
            let path = saveToDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }

            let signatureClient = SignatureClient(fileManager: .default, filePath: path.path)

            try downloadClient.download(from: item.url, to: path) { progress in
                self.onProgress?(progress)
            }

            try signatureClient.appendMetadata(item: item, email: email)
            try signatureClient.appendSignature(item: item)

            return path
        }
    }
}
