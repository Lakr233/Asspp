//
//  Authenticate.swift
//
//
//  Created by QAQ on 2023/10/4.
//

import AsyncHTTPClient
import Foundation

public enum Authenticator {
    private enum LoginResponse {
        case success(Account)
        case codeRequired
        case redirect(URL)
        case retry
        case failure(String)
    }

    public nonisolated static func authenticate(
        email: String,
        password: String,
        code: String = "",
        cookies: [Cookie] = []
    ) async throws -> Account {
        let deviceIdentifier = Configuration.deviceIdentifier

        let client = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: .init(
                tlsConfiguration: Configuration.tlsConfiguration,
                redirectConfiguration: .disallow,
                timeout: .init(
                    connect: .seconds(Configuration.timeoutConnect),
                    read: .seconds(Configuration.timeoutRead)
                ),
            ).then { $0.httpVersion = .http1Only }
        )
        defer { _ = client.shutdown() }

        var requestEndpoint: URL = try createInitialRequestEndpoint(deviceIdentifier: deviceIdentifier)
        var cookies: [Cookie] = cookies
        var storeFront = ""
        var currentAttempt = 1
        var redirectAttempt = 0
        var lastError: Error?

        while currentAttempt <= 2, redirectAttempt <= 3 {
            defer { currentAttempt += 1 }
            do {
                let request = try makeRequest(
                    endpoint: requestEndpoint,
                    email: email,
                    password: password,
                    code: code,
                    cookies: cookies,
                    deviceIdentifier: deviceIdentifier
                )
                let response = try await client.execute(request: request).get()
                let result = try parseResponse(
                    response,
                    email: email,
                    password: password,
                    code: code,
                    cookies: &cookies,
                    storeFront: &storeFront
                )
                switch result {
                case let .success(account):
                    return account
                case let .redirect(uRL):
                    requestEndpoint = uRL
                    currentAttempt -= 1 // allow one more attempt when redirect
                    redirectAttempt += 1
                    continue
                case .codeRequired:
                    currentAttempt += 65535 // stop attempts
                    try ensureFailed("Authentication requires verification code\nIf no verification code prompted, try logging in at https://account.apple.com to trigger the alert and fill the code in the 2FA Code here.")
                case .retry:
                    continue
                case let .failure(string):
                    try ensureFailed("authentication failed: \(string)")
                }
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        try ensureFailed("authentication failed for an unknown reason")
    }

    public nonisolated static func rotatePasswordToken(for account: inout Account) async throws {
        let newAccount = try await authenticate(
            email: account.email,
            password: account.password,
            code: "",
            cookies: account.cookie
        )
        account = newAccount
    }

    private nonisolated static func createInitialRequestEndpoint(
        deviceIdentifier: String
    ) throws -> URL {
        // https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate?guid=xxxxxx
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "buy.itunes.apple.com"
        comps.path = "/WebObjects/MZFinance.woa/wa/authenticate"
        comps.queryItems = [
            URLQueryItem(name: "guid", value: deviceIdentifier),
        ]
        return try comps.url.get()
    }

    private nonisolated static func makeRequest(
        endpoint: URL,
        email: String,
        password: String,
        code: String,
        cookies: [Cookie],
        deviceIdentifier: String
    ) throws -> HTTPClient.Request {
        let parameters: [String: String] = [
            "appleId": email,
            "attempt": "\(code.isEmpty ? "4" : "2")",
            "guid": deviceIdentifier,
            "password": "\(password)\(code)",
            "rmp": "0",
            "why": "signIn",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: parameters,
            format: .xml,
            options: 0
        )
        var headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Content-Type", "application/x-apple-plist"),
        ]
        for item in cookies.buildCookieHeader(endpoint) {
            headers.append(item)
        }
        return try .init(
            url: endpoint.absoluteString,
            method: .POST,
            headers: .init(headers),
            body: .data(data)
        )
    }

    private nonisolated static func parseResponse(
        _ response: HTTPClient.Response,
        email: String,
        password: String,
        code: String,
        cookies: inout [Cookie],
        storeFront: inout String
    ) throws -> LoginResponse {
        cookies.mergeCookies(response.cookies)

        let readStoreFrontValue = response
            .headers["x-set-apple-store-front"]
            .filter { !$0.isEmpty }
            .compactMap { $0.components(separatedBy: "-").first }
            .filter { !$0.isEmpty }
        assert(readStoreFrontValue.count <= 1)
        if let first = readStoreFrontValue.first {
            storeFront = first
        }

        if response.status == .found {
            guard let location = response.headers.first(name: "location"),
                  let url = URL(string: location)
            else {
                return .failure("failed to retrieve redirect location")
            }
            return .redirect(url)
        }

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            return .failure("response body is empty")
        }

        let listItem = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let dic = try (listItem as? [String: Any]).get("response is not a dictionary")

        if let failureType = dic["failureType"] as? String,
           failureType.isEmpty,
           code.isEmpty,
           let customerMessage = dic["customerMessage"] as? String,
           customerMessage == "MZFinance.BadLogin.Configurator_message"
        {
            return .codeRequired
        }

        let failureMessage = (dic["dialog"] as? [String: Any])?["explanation"] as? String ?? (dic["customerMessage"] as? String)
        let accountInfoDic = try (dic["accountInfo"] as? [String: Any]).get(failureMessage ?? "missing accountInfo")
        let addressInfoDic = try (accountInfoDic["address"] as? [String: Any]).get(failureMessage ?? "missing address")

        let account = try Account(
            email: email,
            password: password,
            appleId: accountInfoDic["appleId"] as? String,
            store: storeFront,
            firstName: addressInfoDic["firstName"] as? String,
            lastName: addressInfoDic["lastName"] as? String,
            passwordToken: dic["passwordToken"] as? String,
            directoryServicesIdentifier: dic["dsPersonId"] as? String,
            cookie: cookies
        )
        return .success(account)
    }
}
