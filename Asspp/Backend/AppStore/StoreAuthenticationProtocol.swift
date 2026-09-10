import Foundation

enum StoreAuthenticationError: LocalizedError {
    case codeRequired
    case invalidCode
    case invalidConfiguration
    case invalidRedirect
    case serviceResponse(Int)
    case signingFailed
    case rejected(String, String)
    case tooManyAttempts

    var needsCode: Bool {
        switch self {
        case .codeRequired, .invalidCode: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .codeRequired:
            String(localized: "Enter the verification code sent by Apple, then authenticate again.")
        case .invalidCode:
            String(localized: "The verification code was rejected. Enter a new code and try again.")
        case .invalidConfiguration:
            String(localized: "Apple returned an unsupported login configuration. Update the app and try again.")
        case .invalidRedirect:
            String(localized: "Apple returned an invalid login redirect. No credentials were forwarded.")
        case let .serviceResponse(status):
            String(localized: "Apple's login service returned an unexpected response (HTTP \(status)). This response does not indicate an incorrect password or a missing verification code. Try again later.")
        case .signingFailed:
            String(localized: "The local authentication signer failed. Rebuild or update the app and try again.")
        case let .rejected(code, message):
            message.isEmpty ? String(localized: "Apple rejected the login (code: \(code)).") : message
        case .tooManyAttempts:
            String(localized: "Apple's login service exceeded the retry limit. Try again later.")
        }
    }
}

/// Pure protocol rules, shared by production requests and regression checks.
enum StoreAuthenticationProtocol {
    static let authenticationPath = "/WebObjects/MZFinance.woa/wa/authenticate"

    static func authenticationURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https",
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              host == "buy.itunes.apple.com" || host.range(of: #"^p[0-9]+-buy\.itunes\.apple\.com$"#, options: .regularExpression) != nil,
              url.path == authenticationPath
        else { throw StoreAuthenticationError.invalidRedirect }
        return url
    }

    static func body(email: String, password: String, code: String, guid: String, attempt: Int) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "appleId": email,
            "password": password + code.filter { !$0.isWhitespace },
            "guid": guid,
            "attempt": String(attempt),
            "rmp": "0",
            "why": "signIn",
        ], format: .xml, options: 0)
    }

    static func retryable(status: Int, data: Data) -> Bool {
        // Only retry unstructured transient responses, never a credential/2FA rejection.
        guard StoreProtocol.plist(data) == nil else { return false }
        return status == 204 || status == 404 || (500 ... 599).contains(status)
    }

    static func rejection(_ plist: [String: Any], code: String) -> StoreAuthenticationError? {
        let failure = StoreProtocol.string(plist["failureType"])
        let message = StoreProtocol.string(plist["customerMessage"])
        if failure.isEmpty, code.isEmpty, message == "MZFinance.BadLogin.Configurator_message" {
            return .codeRequired
        }
        if failure == "5005" {
            return .invalidCode
        }
        if !failure.isEmpty {
            return .rejected(failure, message)
        }
        if message == "Your account is disabled." || message == "MZFinance.AccountDisabled_message" {
            return .rejected("", message)
        }
        return nil
    }

    static func storeIdentifier(_ header: String) -> String {
        String(header.split(whereSeparator: { $0 == "-" || $0 == "," }).first ?? "")
    }
}
