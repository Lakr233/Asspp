//
//  AppStore.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Foundation

@Observable
@MainActor
class AppStore {
    @ObservationIgnored
    private var _accounts = Persist<[UserAccount]>(
        key: "Accounts",
        defaultValue: [],
        engine: KeychainStorage(service: "wiki.qaq.Asspp.Accounts"),
    )

    var accounts: [UserAccount] {
        get {
            access(keyPath: \.accounts)
            return _accounts.wrappedValue
        }
        set {
            withMutation(keyPath: \.accounts) {
                _accounts.wrappedValue = newValue
            }
        }
    }

    @ObservationIgnored
    private var _deviceIdentifier = Persist<String>(
        key: "DeviceIdentifier",
        defaultValue: "",
        engine: KeychainStorage(service: "wiki.qaq.Asspp.DeviceIdentifier"),
    )

    var deviceIdentifier: String {
        get {
            access(keyPath: \.deviceIdentifier)
            return _deviceIdentifier.wrappedValue
        }
        set {
            withMutation(keyPath: \.deviceIdentifier) {
                _deviceIdentifier.wrappedValue = newValue
            }
            ApplePackage.Configuration.deviceIdentifier = newValue
        }
    }

    @ObservationIgnored
    private var _demoMode = Persist<Bool>(key: "DemoMode", defaultValue: false)

    var demoMode: Bool {
        get {
            access(keyPath: \.demoMode)
            return _demoMode.wrappedValue
        }
        set {
            withMutation(keyPath: \.demoMode) {
                _demoMode.wrappedValue = newValue
            }
        }
    }

    static let this = AppStore()

    static func normalizedDeviceIdentifier(_ value: String) -> String? {
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard identifier.utf8.count == 12,
              identifier.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) }),
              !["020000000000", "000000000000", "FFFFFFFFFFFF"].contains(identifier)
        else { return nil }
        return identifier
    }

    private init() {
        // Preserve identifiers used by existing accounts until the user edits them.
        if deviceIdentifier.isEmpty || (accounts.isEmpty && Self.normalizedDeviceIdentifier(deviceIdentifier) == nil) {
            if let systemIdentifier = (try? ApplePackage.DeviceIdentifier.system()).flatMap(Self.normalizedDeviceIdentifier) {
                deviceIdentifier = systemIdentifier
                logger.info("obtained system device identifier")
            } else {
                logger.info("using a generated device identifier")
                var randomIdentifier = ApplePackage.DeviceIdentifier.random()
                while Self.normalizedDeviceIdentifier(randomIdentifier) == nil {
                    randomIdentifier = ApplePackage.DeviceIdentifier.random()
                }
                deviceIdentifier = randomIdentifier
            }
        }
        ApplePackage.Configuration.deviceIdentifier = deviceIdentifier
    }

    @discardableResult
    func save(email: String, account: ApplePackage.Account) throws -> UserAccount {
        logger.info("saving account for user")
        let account = UserAccount(account: account)
        let updatedAccounts = (accounts.filter { $0.account.email != email } + [account])
            .sorted { $0.account.email < $1.account.email }
        do {
            try withMutation(keyPath: \.accounts) {
                try _accounts.setAndSave(updatedAccounts)
            }
        } catch {
            throw AccountStorageError()
        }
        return account
    }

    private struct AccountStorageError: LocalizedError {
        var errorDescription: String? {
            String(localized: "Unable to save the account to Keychain. Check the app's code signing and Keychain access, then try again.")
        }
    }

    func delete(id: UserAccount.ID) {
        logger.info("deleting account id: \(id)")
        accounts = accounts.filter { $0.id != id }
    }

    var possibleRegions: Set<String> {
        Set(accounts.compactMap { ApplePackage.Configuration.countryCode(for: $0.account.store) })
    }

    func eligibleAccounts(for region: String) -> [UserAccount] {
        accounts.filter { ApplePackage.Configuration.countryCode(for: $0.account.store) == region }
    }

    nonisolated func withAccount<T>(id: String, _ body: (inout UserAccount) async throws -> T) async throws -> T {
        guard var account = await accounts.first(where: { $0.id == id }) else {
            throw AuthenticationError.accountNotFound
        }
        let result = try await body(&account)
        let updatedAccount = account
        // Re-resolve by id: the accounts array may have been mutated (added,
        // removed, re-sorted) during the await, so the original index is stale.
        await MainActor.run {
            if let idx = accounts.firstIndex(where: { $0.id == id }) {
                accounts[idx] = updatedAccount
            }
        }
        return result
    }
}
