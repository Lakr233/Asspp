//
//  Authenticate.swift
//
//
//  Created by QAQ on 2023/10/4.
//

import Foundation

public extension ApplePackage {
    class Authenticator {
        public let email: String
        public var authenticated: Bool { authenticatedAccount != nil }

        private let storeClient: StoreClient
        private var authenticatedAccount: StoreResponse.Account?

        public init(email: String) {
            self.email = email
            let httpClient = HTTPClient(urlSession: URLSession.shared)
            storeClient = StoreClient(httpClient: httpClient)
        }

        public func authenticate(password: String, code: String?) throws -> StoreResponse.Account {
            if let account = authenticatedAccount { return account }
            let account = try storeClient.authenticate(email: email, password: password, code: code)
            authenticatedAccount = account
            return account
        }
    }
}
