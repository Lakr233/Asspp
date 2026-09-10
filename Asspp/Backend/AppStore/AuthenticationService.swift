//
//  AuthenticationService.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Foundation
import Logging

extension AppStore {
    enum AuthenticationError: LocalizedError {
        case accountNotFound

        var errorDescription: String? {
            String(localized: "The selected account no longer exists. Add it again to continue.")
        }
    }

    @MainActor
    func authenticate(email: String, password: String, code: String) async throws -> UserAccount {
        logger.info("starting authentication for user")
        do {
            let appleAccount = try await SignedStoreAuthenticator().authenticate(
                email: email,
                password: password,
                code: code,
                guid: deviceIdentifier,
                cookies: []
            )
            let userAccount = save(email: email, account: appleAccount)
            logger.info("authentication successful for user")
            return userAccount
        } catch {
            logger.error("authentication failed: \(StoreDiagnostics.errorSummary(error))")
            throw error
        }
    }

    @MainActor
    @discardableResult
    func rotate(id: UserAccount.ID) async throws -> UserAccount? {
        logger.info("starting account rotation")
        guard let account = accounts.first(where: { $0.id == id }) else {
            logger.error("account not found for rotation")
            throw AuthenticationError.accountNotFound
        }
        do {
            let newAppleAccount = try await SignedStoreAuthenticator().authenticate(
                email: account.account.email,
                password: account.account.password,
                code: "",
                guid: deviceIdentifier,
                cookies: account.account.cookie
            )
            let updatedAccount = save(email: account.account.email, account: newAppleAccount)
            logger.info("account rotation successful")
            return updatedAccount
        } catch {
            logger.error("account rotation failed: \(StoreDiagnostics.errorSummary(error))")
            throw error
        }
    }
}
