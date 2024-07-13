//
//  AppStore.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Combine
import Foundation

class AppStore: ObservableObject {
    struct Account: Codable, Identifiable, Hashable {
        var id: String { email }

        var email: String
        var password: String
        var countryCode: String
        var storeResponse: StoreResponse.Account
    }

    var cancellables: Set<AnyCancellable> = .init()

    @PublishedPersist(key: "DeviceSeedAddress", defaultValue: "")
    var deviceSeedAddress: String

    static func createSeed() -> String {
        "00:00:00:00:00:00"
            .components(separatedBy: ":")
            .map { _ in
                let randomHex = String(Int.random(in: 0 ... 255), radix: 16)
                return randomHex.count == 1 ? "0\(randomHex)" : randomHex
            }
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
    }

    @PublishedPersist(key: "Accounts", defaultValue: [])
    var accounts: [Account]

    @PublishedPersist(key: "DemoMode", defaultValue: false)
    var demoMode: Bool

    static let this = AppStore()
    private init() {
        $deviceSeedAddress
            .removeDuplicates()
            .sink { input in
                print("[*] updating guid \(input) as the seed")
                ApplePackage.overrideGUID = input
            }
            .store(in: &cancellables)
    }

    func setupGUID() {
        if deviceSeedAddress.isEmpty { deviceSeedAddress = Self.createSeed() }
        assert(!deviceSeedAddress.isEmpty)
        deviceSeedAddress = deviceSeedAddress
    }

    @discardableResult
    func save(email: String, password: String, account: StoreResponse.Account) -> Account {
        let account = Account(
            email: email,
            password: password,
            countryCode: account.countryCode,
            storeResponse: account
        )
        accounts = accounts
            .filter { $0.email.lowercased() != email.lowercased() }
            + [account]
        return account
    }

    func delete(id: Account.ID) {
        accounts = accounts.filter { $0.id != id }
    }

    @discardableResult
    func rotate(id: Account.ID) throws -> Account? {
        guard let account = accounts.first(where: { $0.id == id }) else { return nil }
        let auth = ApplePackage.Authenticator(email: account.email)
        let newAccount = try auth.authenticate(password: account.password, code: nil)
        if Thread.isMainThread {
            return save(email: account.email, password: account.password, account: newAccount)
        } else {
            var result: Account?
            DispatchQueue.main.asyncAndWait {
                result = self.save(email: account.email, password: account.password, account: newAccount)
            }
            return result
        }
    }
}
