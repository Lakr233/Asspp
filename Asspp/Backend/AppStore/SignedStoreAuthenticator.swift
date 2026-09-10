import ApplePackage
import Foundation

/// One isolated transport and signer per login. Credentials only go to validated Apple endpoints.
actor SignedStoreAuthenticator {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_: URLSession, task _: URLSessionTask,
                        willPerformHTTPRedirection _: HTTPURLResponse,
                        newRequest _: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void)
        {
            completionHandler(nil)
        }
    }

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let userAgent = ApplePackage.Configuration.userAgent

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        cookieStorage = configuration.httpCookieStorage!
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }

    func authenticate(email: String, password: String, code: String, guid: String, cookies: [Cookie]) async throws -> ApplePackage.Account {
        defer { session.invalidateAndCancel() }
        do {
            return try await performAuthentication(email: email, password: password, code: code, guid: guid, cookies: cookies)
        } catch where (error as NSError).domain == "Asspp.SAP" {
            throw StoreAuthenticationError.signingFailed
        }
    }

    private func performAuthentication(email: String, password: String, code: String, guid: String, cookies: [Cookie]) async throws -> ApplePackage.Account {
        try Task.checkCancellation()
        let normalizedCode = code.filter { !$0.isWhitespace }
        restore(cookies)
        guard guid.count == 12, guid.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw StoreAuthenticationError.invalidConfiguration
        }
        var bagComponents = URLComponents(string: "https://init.itunes.apple.com/bag.xml")!
        bagComponents.queryItems = [URLQueryItem(name: "guid", value: guid)]
        let bagURL = bagComponents.url!
        let (bagData, bagResponse) = try await send(URLRequest(url: bagURL))
        guard bagResponse.statusCode == 200, let bag = StoreProtocol.plist(bagData) else {
            throw StoreAuthenticationError.serviceResponse(bagResponse.statusCode)
        }
        let nested = bag["urlBag"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Any? {
            bag[key] ?? nested[key]
        }
        let endpoint = try StoreAuthenticationProtocol.authenticationURL(StoreProtocol.string(value("authenticateAccount")))
        guard StoreProtocol.string(value("sign-sap-version")) == "200",
              let certificateURL = publicSAPURL(value("sign-sap-setup-cert"), host: "s.mzstatic.com"),
              let setupURL = publicSAPURL(value("sign-sap-setup"), host: "fpinit.itunes.apple.com"),
              let assets = Bundle.main.resourceURL?.appendingPathComponent("SAPAssets"),
              guid.count == 12
        else { throw StoreAuthenticationError.invalidConfiguration }
        let hardware = stride(from: 0, to: 12, by: 2).compactMap { offset -> UInt8? in
            let start = guid.index(guid.startIndex, offsetBy: offset)
            return UInt8(guid[start ..< guid.index(start, offsetBy: 2)], radix: 16)
        }
        guard hardware.count == 6 else { throw StoreAuthenticationError.invalidConfiguration }
        let signer = try SAPContext(assetsURL: assets, hardwareID: Data(hardware))
        let (certificateData, certificateResponse) = try await send(URLRequest(url: certificateURL))
        guard certificateResponse.statusCode == 200,
              let certificate = StoreProtocol.plist(certificateData)?["sign-sap-setup-cert"] as? Data
        else { throw StoreAuthenticationError.serviceResponse(certificateResponse.statusCode) }
        let exchange = try signer.exchangeData(certificate, version: 200)
        var setup = URLRequest(url: setupURL)
        setup.httpMethod = "POST"
        setup.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        setup.httpBody = try PropertyListSerialization.data(fromPropertyList: ["sign-sap-setup-buffer": exchange], format: .xml, options: 0)
        let (setupData, setupResponse) = try await send(setup)
        guard setupResponse.statusCode == 200,
              let reply = StoreProtocol.plist(setupData)?["sign-sap-setup-buffer"] as? Data
        else { throw StoreAuthenticationError.serviceResponse(setupResponse.statusCode) }
        _ = try signer.exchangeData(reply, version: 200)
        guard signer.complete else { throw StoreAuthenticationError.invalidConfiguration }

        var url = endpoint
        var protocolAttempt = 1
        var redirects = 0
        var storefront = ""
        var pod: String?
        var body = try StoreAuthenticationProtocol.body(email: email, password: password, code: normalizedCode, guid: guid, attempt: protocolAttempt)
        while protocolAttempt <= 2, redirects <= 3 {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await sendAuthentication(request, signer: signer)
            if let value = response.value(forHTTPHeaderField: "X-Set-Apple-Store-Front") {
                storefront = value
            }
            if let value = response.value(forHTTPHeaderField: "pod") {
                pod = value
            }
            if (300 ... 399).contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location") else {
                    throw StoreAuthenticationError.serviceResponse(response.statusCode)
                }
                guard let next = URL(string: location, relativeTo: url)?.absoluteURL else { throw StoreAuthenticationError.invalidRedirect }
                url = try StoreAuthenticationProtocol.authenticationURL(next.absoluteString)
                redirects += 1
                continue
            }
            guard let plist = StoreProtocol.plist(data) else {
                throw StoreAuthenticationError.serviceResponse(response.statusCode)
            }
            // Apple's initial -5000 reply may be a protocol challenge, as in ipatool 2.5.
            if protocolAttempt == 1, StoreProtocol.string(plist["failureType"]) == "-5000" {
                protocolAttempt += 1
                body = try StoreAuthenticationProtocol.body(email: email, password: password, code: normalizedCode, guid: guid, attempt: protocolAttempt)
                continue
            }
            if let error = StoreAuthenticationProtocol.rejection(plist, code: normalizedCode) {
                throw error
            }
            guard response.statusCode == 200,
                  let info = plist["accountInfo"] as? [String: Any],
                  let address = info["address"] as? [String: Any],
                  let token = plist["passwordToken"] as? String, !token.isEmpty,
                  !StoreProtocol.string(plist["dsPersonId"]).isEmpty
            else { throw StoreAuthenticationError.serviceResponse(response.statusCode) }
            let store = StoreAuthenticationProtocol.storeIdentifier(storefront)
            guard !store.isEmpty else {
                throw StoreAuthenticationError.invalidConfiguration
            }
            return try ApplePackage.Account(
                email: email, password: password,
                appleId: info["appleId"] as? String,
                store: store,
                firstName: address["firstName"] as? String,
                lastName: address["lastName"] as? String,
                passwordToken: token,
                directoryServicesIdentifier: StoreProtocol.string(plist["dsPersonId"]),
                cookie: savedCookies(), pod: pod
            )
        }
        throw StoreAuthenticationError.tooManyAttempts
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ", "), forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw StoreAuthenticationError.serviceResponse(0) }
        // Do not log bodies, signatures, URL query strings, or Set-Cookie headers.
        logger.info("Apple authentication: HTTP \(response.statusCode), \(data.count) bytes")
        return (data, response)
    }

    private func sendAuthentication(_ request: URLRequest, signer: SAPContext) async throws -> (Data, HTTPURLResponse) {
        for attempt in 1 ... 3 {
            var signedRequest = request
            // Retry the identical body with a fresh signature, as ipatool does.
            try signedRequest.setValue(signer.sign(request.httpBody ?? Data()).base64EncodedString(), forHTTPHeaderField: "X-Apple-ActionSignature")
            let result = try await send(signedRequest)
            if attempt == 3 || !StoreAuthenticationProtocol.retryable(status: result.1.statusCode, data: result.0) {
                return result
            }
            try await Task.sleep(for: .milliseconds(attempt * 250))
        }
        throw StoreAuthenticationError.tooManyAttempts
    }

    private func publicSAPURL(_ value: Any?, host: String) -> URL? {
        guard let text = value as? String, let url = URL(string: text),
              url.scheme == "https", url.host?.lowercased() == host,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url
    }

    private func restore(_ cookies: [Cookie]) {
        for cookie in cookies {
            guard let domain = StoreProtocol.foundationCookieDomain(cookie.domain) else { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name, .value: cookie.value, .path: cookie.path, .domain: domain,
                .secure: cookie.secure ? "TRUE" : "FALSE",
            ]
            if let expires = cookie.expiresAt {
                properties[.expires] = Date(timeIntervalSince1970: expires)
            }
            if cookie.httpOnly {
                properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
            }
            if let restored = HTTPCookie(properties: properties) {
                cookieStorage.setCookie(restored)
            }
        }
    }

    private func savedCookies() -> [Cookie] {
        (cookieStorage.cookies ?? []).map {
            Cookie(name: $0.name, value: $0.value, path: $0.path, domain: StoreProtocol.storeCookieDomain($0.domain),
                   expiresAt: $0.expiresDate?.timeIntervalSince1970, httpOnly: $0.isHTTPOnly, secure: $0.isSecure)
        }
    }
}
