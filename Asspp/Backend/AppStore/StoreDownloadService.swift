import ApplePackage
import Foundation

/// Download metadata transport. Keep Apple's raw bodies, cookies and signed
/// asset URLs out of both the Xcode console and the in-app log viewer.
enum StoreDownloadService {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_: URLSession, task _: URLSessionTask,
                        willPerformHTTPRedirection _: HTTPURLResponse,
                        newRequest _: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void)
        {
            completionHandler(nil)
        }
    }

    static func download(account: inout Account, package: AppStore.AppPackage) async throws -> DownloadOutput {
        let email = account.email
        return try await product(account: &account, package: package, version: package.externalVersionID, operation: "download") { item in
            try output(item: item, email: email)
        }
    }

    static func versions(account: inout Account, package: AppStore.AppPackage) async throws -> [String] {
        try await product(account: &account, package: package, version: nil, operation: "versions") { item in
            guard let metadata = item["metadata"] as? [String: Any],
                  let identifiers = metadata["softwareVersionExternalIdentifiers"] as? [Any]
            else { throw StoreDownloadError.noVersions }
            let versions = identifiers.map { StoreProtocol.string($0) }.filter { !$0.isEmpty }
            guard !versions.isEmpty else { throw StoreDownloadError.noVersions }
            return versions
        }
    }

    static func versionMetadata(account: inout Account, package: AppStore.AppPackage, versionID: String) async throws -> VersionMetadata {
        try await product(account: &account, package: package, version: versionID, operation: "version-metadata") { item in
            guard let metadata = item["metadata"] as? [String: Any],
                  let version = metadata["bundleShortVersionString"] as? String,
                  let dateString = metadata["releaseDate"] as? String,
                  let releaseDate = ISO8601DateFormatter().date(from: dateString)
            else { throw StoreDownloadError.invalidPackage }
            return VersionMetadata(displayVersion: version, releaseDate: releaseDate)
        }
    }

    private static func product<Result>(account: inout Account, package: AppStore.AppPackage, version: String?, operation: String, parse: ([String: Any]) throws -> Result) async throws -> Result {
        let trace = String(UUID().uuidString.prefix(8))
        let app = package.software
        let version = version.flatMap { $0.isEmpty ? nil : $0 }
        let platform = package.entityType ?? .iPhone
        logger.info("Store download [\(trace)]: operation=\(operation) app=\(app.id) platform=\(platform.rawValue) store=\(account.store) version=\(version ?? "latest")")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let region = Configuration.countryCode(for: account.store)
            var effectiveVersion = version
            let response = try await StoreDownloadProtocol.fetchWithFallback(version: version) { endpoint, requestedVersion in
                effectiveVersion = requestedVersion
                return try await fetch(session: session, endpoint: endpoint, account: &account,
                                       appID: app.id, version: requestedVersion, trace: trace)
            } resolveVersion: {
                // An unpinned redownload can return a tvOS build for an iOS app.
                guard let region else { throw StoreDownloadError.catalogUnavailable }
                let metadata: StoreDownloadProtocol.CatalogVersion
                do {
                    metadata = try await catalogVersion(session: session, appID: app.id, region: region, platform: platform, trace: trace)
                } catch {
                    try Task.checkCancellation()
                    throw StoreDownloadError.catalogUnavailable
                }
                guard !metadata.externalVersionID.isEmpty,
                      metadata.bundleID == nil || metadata.bundleID == app.bundleID
                else { throw StoreDownloadError.catalogUnavailable }
                logger.info("Store download [\(trace)]: catalog version=\(metadata.externalVersionID)")
                return metadata.externalVersionID
            } onFallback: { reason in
                logger.info("Store download [\(trace)]: trying redownload, reason=\(reason)")
            }
            // Preserve the existing UI's explicit free-license acquisition flow.
            if StoreDownloadProtocol.failureCode(response) == "9610" {
                throw ApplePackageError.licenseRequired
            }
            let item = try StoreDownloadProtocol.packageItem(response, bundleID: app.bundleID, version: effectiveVersion)
            let result = try parse(item)
            logger.info("Store download [\(trace)]: product metadata ready")
            return result
        } catch {
            // localizedDescription and NSError.userInfo can contain Apple messages
            // or a credential-bearing URL. Log only the error type and numeric code.
            logger.error("Store download [\(trace)]: failed, \(StoreDiagnostics.errorSummary(error))")
            throw error
        }
    }

    private static func catalogVersion(session: URLSession, appID: Int64, region: String, platform: EntityType, trace: String) async throws -> StoreDownloadProtocol.CatalogVersion {
        var url = URLComponents(string: "https://uclient-api.itunes.apple.com/WebObjects/MZStorePlatform.woa/wa/lookup")!
        url.queryItems = [
            URLQueryItem(name: "version", value: "2"), URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "p", value: "mdm-lockup"), URLQueryItem(name: "caller", value: "MDM"),
            URLQueryItem(name: "platform", value: platform == .appleTV ? "atv9" : "enterprisestore"),
            URLQueryItem(name: "cc", value: region.lowercased()), URLQueryItem(name: "l", value: "en"),
        ]
        var request = URLRequest(url: url.url!)
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        // No credentials and no automatic redirects. Foundation verifies TLS in
        // Debug too (ApplePackage 1.2.7 disables verification in its Debug client).
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.info("Store download [\(trace)]: catalog HTTP=\(status) bytes=\(data.count)")
        guard status == 200 else { throw StoreDownloadError.catalogUnavailable }
        return try StoreDownloadProtocol.catalogVersion(data, appID: appID)
    }

    private static func fetch(session: URLSession, endpoint: StoreDownloadProtocol.Endpoint,
                              account: inout Account, appID: Int64, version: String?, trace: String) async throws -> [String: Any]
    {
        var components = URLComponents()
        components.scheme = "https"
        components.host = endpoint == .volumeStore ? Configuration.storeAPIHost(pod: account.pod) : "downloaddispatch.itunes.apple.com"
        components.path = endpoint.path
        components.queryItems = [URLQueryItem(name: "guid", value: Configuration.deviceIdentifier)]
        guard var url = components.url else { throw StoreDownloadError.invalidRedirect }
        let body = try PropertyListSerialization.data(
            fromPropertyList: StoreDownloadProtocol.payload(endpoint: endpoint, appID: appID,
                                                            guid: Configuration.deviceIdentifier, version: version),
            format: .xml, options: 0
        )
        for redirect in 0 ... 3 {
            try Task.checkCancellation()
            url = try StoreDownloadProtocol.validatedURL(url)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
            request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ", "), forHTTPHeaderField: "Accept-Language")
            request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
            request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")
            for (name, value) in account.cookie.buildCookieHeader(url) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            logger.info("Store download [\(trace)]: endpoint=\(endpoint.rawValue) hop=\(redirect) sessionCookie=\(request.value(forHTTPHeaderField: "Cookie") != nil)")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw StoreDownloadError.response(0) }
            mergeCookies(response: response, url: url, account: &account)
            logger.info("Store download [\(trace)]: endpoint=\(endpoint.rawValue) HTTP=\(response.statusCode) bytes=\(data.count)")
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard redirect < 3, let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL
                else { throw StoreDownloadError.invalidRedirect }
                url = try StoreDownloadProtocol.validatedURL(next)
                continue
            }
            let plist = StoreProtocol.plist(data)
            if let plist {
                logger.info("Store download [\(trace)]: \(StoreDownloadProtocol.summary(plist))")
            }
            guard response.statusCode == 200, let plist else { throw StoreDownloadError.response(response.statusCode) }
            return plist
        }
        throw StoreDownloadError.invalidRedirect
    }

    private static func mergeCookies(response: HTTPURLResponse, url: URL, account: inout Account) {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let name = field.key as? String, let value = field.value as? String {
                result[name] = value
            }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            let domain = StoreProtocol.storeCookieDomain(cookie.domain)
            account.cookie.removeAll { $0.name == cookie.name && $0.path == cookie.path && StoreProtocol.storeCookieDomain($0.domain) == domain }
            if let expiry = cookie.expiresDate, expiry <= Date() {
                continue
            }
            account.cookie.append(Cookie(name: cookie.name, value: cookie.value, path: cookie.path, domain: domain,
                                         expiresAt: cookie.expiresDate?.timeIntervalSince1970, httpOnly: cookie.isHTTPOnly, secure: cookie.isSecure))
        }
    }

    /// ApplePackage's DownloadOutput format, also consumed by SignatureInjector.
    private static func output(item: [String: Any], email: String) throws -> DownloadOutput {
        guard let url = item["URL"] as? String, let asset = URL(string: url),
              ["https", "http"].contains(asset.scheme), asset.host != nil,
              var metadata = item["metadata"] as? [String: Any],
              let version = metadata["bundleShortVersionString"] as? String,
              let build = metadata["bundleVersion"] as? String,
              let signatures = item["sinfs"] as? [[String: Any]], !signatures.isEmpty
        else { throw StoreDownloadError.invalidPackage }
        let sinfs = try signatures.map { signature -> Sinf in
            guard let id = signature["id"] as? Int64, let data = signature["sinf"] as? Data else {
                throw StoreDownloadError.invalidPackage
            }
            return Sinf(id: id, sinf: data)
        }
        metadata["apple-id"] = email
        metadata["userName"] = email
        return try DownloadOutput(downloadURL: url, sinfs: sinfs, bundleShortVersionString: version,
                                  bundleVersion: build, iTunesMetadata: PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0))
    }
}
