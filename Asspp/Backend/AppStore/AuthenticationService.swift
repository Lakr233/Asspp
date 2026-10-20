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
    enum AuthenticationError: Error {
        case accountNotFound
    }

    @MainActor
    func authenticate(email: String, password: String, code: String, using session: ApplePackage.Authenticator) async throws -> UserAccount {
        logger.info("starting authentication for user")
        do {
            let appleAccount = try await session.authenticate(
                email: email,
                password: password,
                code: code,
            )
            let userAccount = save(email: email, account: appleAccount)
            logger.info("authentication successful for user")
            return userAccount
        } catch {
            logger.error("authentication failed for user: \(error.localizedDescription)")
            throw error
        }
    }

    @MainActor
    @discardableResult
    func rotate(id: UserAccount.ID) async throws -> UserAccount? {
        logger.info("starting account rotation for user id: \(id)")
        guard let account = accounts.first(where: { $0.id == id }) else {
            logger.error("account not found for rotation, id: \(id)")
            throw AuthenticationError.accountNotFound
        }
        do {
            let newAppleAccount = try await ApplePackage.Authenticator.authenticate(
                email: account.account.email,
                password: account.account.password,
                code: "",
                cookies: account.account.cookie,
            )
            let updatedAccount = save(email: account.account.email, account: newAppleAccount)
            logger.info("account rotation successful for user id: \(id)")
            return updatedAccount
        } catch {
            logger.error("account rotation failed for user id: \(id): \(error.localizedDescription)")
            throw error
        }
    }
}
