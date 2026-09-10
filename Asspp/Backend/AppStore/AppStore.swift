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

    private init() {
        if deviceIdentifier.isEmpty {
            do {
                let systemIdentifier = try ApplePackage.DeviceIdentifier.system()
                deviceIdentifier = systemIdentifier
                logger.info("obtained system device identifier")
            } catch {
                logger.warning("failed to get system device identifier, falling back to random one: \(error)")
                let randomIdentifier = ApplePackage.DeviceIdentifier.random()
                deviceIdentifier = randomIdentifier
            }
        }
        logger.info("device identifier configured")
        ApplePackage.Configuration.deviceIdentifier = deviceIdentifier
    }

    @discardableResult
    func save(email: String, account: ApplePackage.Account) -> UserAccount {
        logger.info("saving account for user")
        var account = UserAccount(account: account)
        account.normalizeStoreCookies()
        accounts = (accounts.filter { $0.account.email != email } + [account])
            .sorted { $0.account.email < $1.account.email }
        return account
    }

    func delete(id: UserAccount.ID) {
        logger.info("deleting account")
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
        let originalAccount = account.account
        // Migrate cookies saved by the first SAP release before any store request.
        // This also covers download, version history and license requests.
        account.normalizeStoreCookies()
        let result = try await body(&account)
        account.normalizeStoreCookies()
        let updatedAccount = account
        // Do not overwrite a concurrent login/rotation with this older session.
        // Re-resolve by id: the accounts array may have been mutated (added,
        // removed, re-sorted) during the await, so the original index is stale.
        await MainActor.run {
            if let idx = accounts.firstIndex(where: { $0.id == id }), accounts[idx].account == originalAccount {
                accounts[idx] = updatedAccount
            }
        }
        return result
    }
}
