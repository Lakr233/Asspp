import Foundation

@main
struct DownloadProtocolChecks {
    static func main() async throws {
        let empty: [String: Any] = ["songList": [], "status": 0, "jingleDocType": "purchaseSuccess"]
        let success: [String: Any] = ["songList": [["metadata": ["softwareVersionBundleId": "example.app"]]]]
        var requests: [(StoreDownloadProtocol.Endpoint, String?)] = []
        var lookups = 0
        let result = try await StoreDownloadProtocol.fetchWithFallback(version: nil) { endpoint, version in
            requests.append((endpoint, version))
            return endpoint == .volumeStore ? empty : success
        } resolveVersion: {
            lookups += 1
            return "890598805"
        } onFallback: { precondition($0 == "empty-songList") }
        precondition(requests.count == 2 && requests[0].0 == .volumeStore && requests[0].1 == nil)
        precondition(requests[1].0 == .redownload && requests[1].1 == "890598805" && lookups == 1)
        _ = try StoreDownloadProtocol.packageItem(result, bundleID: "example.app")

        // Preserve historical IDs on both endpoints; numeric 5002 is retryable.
        requests = []
        _ = try await StoreDownloadProtocol.fetchWithFallback(version: "12345") { endpoint, version in
            requests.append((endpoint, version))
            return endpoint == .volumeStore ? ["failureType": 5002] : success
        } resolveVersion: { fatalError("Replaced the requested historical version") }
            onFallback: { precondition($0 == "failure-5002") }
        precondition(requests.count == 2 && requests.allSatisfy { $0.1 == "12345" })

        // A catalog failure never issues an unpinned fallback request.
        requests = []
        do {
            _ = try await StoreDownloadProtocol.fetchWithFallback(version: nil) { endpoint, version in
                requests.append((endpoint, version))
                return empty
            } resolveVersion: { throw StoreDownloadError.catalogUnavailable } onFallback: { _ in }
            fatalError("Ignored catalog failure")
        } catch StoreDownloadError.catalogUnavailable {}
        precondition(requests.count == 1)

        // Successful, rejected and malformed primary responses are not retried.
        for response in [success, ["failureType": "9610"], ["failureType": 2034],
                         ["metrics": ["messageCode": 2042]], ["customerMessage": "Unavailable"],
                         ["songList": [], "dialog": ["kind": "authorization"]],
                         ["action": ["url": "https://example.invalid/termsPage"]],
                         ["status": -1], ["songList": "malformed"]]
        {
            requests = []
            _ = try await StoreDownloadProtocol.fetchWithFallback(version: nil) { endpoint, version in
                requests.append((endpoint, version))
                return response
            } resolveVersion: { fatalError("Unexpected catalog request") }
                onFallback: { _ in fatalError("Unexpected fallback") }
            precondition(requests.count == 1)
        }

        // Even when both endpoints are empty, there is no retry loop.
        requests = []
        let stillEmpty = try await StoreDownloadProtocol.fetchWithFallback(version: "123") { endpoint, version in
            requests.append((endpoint, version))
            return empty
        } resolveVersion: { fatalError("Unexpected lookup") } onFallback: { _ in }
        precondition(requests.count == 2)
        do {
            _ = try StoreDownloadProtocol.packageItem(stillEmpty, bundleID: "example.app")
            fatalError("Accepted an empty package list")
        } catch StoreDownloadError.empty {}
        do {
            _ = try StoreDownloadProtocol.packageItem(success, bundleID: "other.app")
            fatalError("Accepted another app's package")
        } catch StoreDownloadError.invalidPackage {}
        do {
            _ = try StoreDownloadProtocol.packageItem(["failureType": 9610, "customerMessage": "License required"], bundleID: "example.app")
            fatalError("Lost numeric failure code")
        } catch StoreDownloadError.rejected("9610", "License required") {}

        for endpoint in [StoreDownloadProtocol.Endpoint.volumeStore, .redownload] {
            let data = try PropertyListSerialization.data(fromPropertyList: StoreDownloadProtocol.payload(endpoint: endpoint, appID: 123,
                                                                                                          guid: "synthetic", version: "456"), format: .xml, options: 0)
            let payload = StoreProtocol.plist(data)!
            precondition(payload[endpoint.versionKey] as? String == "456")
            precondition(payload[endpoint == .volumeStore ? "appExtVrsId" : "externalVersionId"] == nil)
            precondition(payload["salableAdamId"] as? Int64 == 123)
        }

        let primary = "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        for url in [primary, "https://downloaddispatch.itunes.apple.com/r/redownload?guid=fixture",
                    "https://p71-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/redownloadProduct"]
        {
            _ = try StoreDownloadProtocol.validatedURL(URL(string: url)!)
        }
        for url in [primary.replacingOccurrences(of: "https:", with: "http:"),
                    primary.replacingOccurrences(of: "p25-buy.itunes.apple.com", with: "p25-buy.itunes.apple.com.attacker.invalid"),
                    primary.replacingOccurrences(of: "p25-buy.", with: "user:password@p25-buy."),
                    primary.replacingOccurrences(of: "/wa/volumeStoreDownloadProduct", with: "/wa/buyProduct"),
                    primary + "#fragment", primary.replacingOccurrences(of: ".com/", with: ".com:8080/")]
        {
            do {
                _ = try StoreDownloadProtocol.validatedURL(URL(string: url)!)
                fatalError("Accepted a credential redirect outside the download endpoints")
            } catch StoreDownloadError.invalidRedirect {}
        }

        // Unknown fields and sensitive values must never reach diagnostic logs.
        let secret = "SECRET-user@example.invalid-cookie-token-url"
        let summary = StoreDownloadProtocol.summary([
            "songList": [["URL": secret, "sinfs": [secret]]], "failureType": secret,
            "customerMessage": secret, "passwordToken": secret, "dialog": ["message": secret],
            "status": secret, secret: secret,
        ])
        precondition(!summary.contains(secret) && summary.contains("songList=1") && summary.contains("failure=other"))
        precondition(StoreDownloadProtocol.fallbackReason(["metrics": ["messageCode": 0]]) == "missing-songList")
        // Catalog IDs accept both current offer shapes, never another app's entry.
        func catalog(_ offers: [[String: Any]], id: String = "123") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["results": [id: ["bundleId": "example.app", "offers": offers]]])
        }
        for offers in [[["version": ["externalId": 456]]],
                       [["version": ["externalId": "456"]]],
                       [["buyParams": "price=0&appExtVrsId=456"]],
                       [["version": ["externalId": "invalid"]], ["buyParams": "appExtVrsId=456"]]]
        {
            let version = try StoreDownloadProtocol.catalogVersion(catalog(offers), appID: 123)
            precondition(version.externalVersionID == "456" && version.bundleID == "example.app")
        }
        for data in try [catalog([]), catalog([["buyParams": "appExtVrsId=secret%20value"]]),
                         catalog([["version": ["externalId": 456]]], id: "999")]
        {
            do {
                _ = try StoreDownloadProtocol.catalogVersion(data, appID: 123)
                fatalError("Accepted missing or invalid catalog data")
            } catch StoreDownloadError.catalogUnavailable {}
        }
        do {
            _ = try StoreDownloadProtocol.packageItem(["songList": "invalid"], bundleID: "example.app")
            fatalError("Misclassified a malformed song list")
        } catch StoreDownloadError.invalidPackage {}
        do {
            _ = try StoreDownloadProtocol.packageItem(["songList": [["metadata": [
                "softwareVersionBundleId": "example.app", "softwareVersionExternalIdentifier": 456,
            ]]]], bundleID: "example.app", version: "123")
            fatalError("Accepted a different historical version")
        } catch StoreDownloadError.invalidPackage {}

        // Ignore extension/Watch metadata; validate the main IPA's actual platform.
        precondition(StoreDownloadProtocol.isMainInfoPlist("Payload/Example.app/Info.plist"))
        for path in ["Payload/Example.app/Watch/Watch.app/Info.plist", "Payload/Example.app/PlugIns/Widget.appex/Info.plist",
                     "Payload/../Info.plist", "Payload//Example.app/Info.plist", "Info.plist"]
        {
            precondition(!StoreDownloadProtocol.isMainInfoPlist(path))
        }
        for info in [
            ["CFBundleIdentifier": "example.app", "CFBundleSupportedPlatforms": ["iPhoneOS"]],
            ["CFBundleIdentifier": "example.app", "DTPlatformName": "iphoneos"],
        ] as [[String: Any]] {
            try StoreDownloadProtocol.validatePackageInfo(info, bundleID: "example.app", platform: "iPhoneOS")
        }
        for info in [
            ["CFBundleIdentifier": "other.app", "CFBundleSupportedPlatforms": ["iPhoneOS"]],
            ["CFBundleIdentifier": "example.app", "CFBundleSupportedPlatforms": ["AppleTVOS"]],
            ["CFBundleIdentifier": "example.app"],
        ] as [[String: Any]] {
            do {
                try StoreDownloadProtocol.validatePackageInfo(info, bundleID: "example.app", platform: "iPhoneOS")
                fatalError("Accepted mismatched or missing package identity")
            } catch StoreDownloadError.invalidPackage {}
        }
        let error = NSError(domain: secret, code: 403, userInfo: [NSLocalizedDescriptionKey: secret, NSURLErrorKey: secret])
        precondition(!StoreDiagnostics.errorSummary(error).contains(secret))
        print("Download protocol regression checks passed.")
    }
}
