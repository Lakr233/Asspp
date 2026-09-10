import Foundation

@main
struct AuthenticationProtocolChecks {
    static func main() throws {
        let auth = "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"
        _ = try StoreAuthenticationProtocol.authenticationURL(auth)
        _ = try StoreAuthenticationProtocol.authenticationURL(auth.replacingOccurrences(of: "buy.", with: "p25-buy."))
        for invalid in [
            auth.replacingOccurrences(of: "https:", with: "http:"),
            auth.replacingOccurrences(of: "buy.itunes.apple.com", with: "buy.itunes.apple.com.attacker.example"),
            auth.replacingOccurrences(of: "buy.itunes.apple.com", with: "attacker-buy.itunes.apple.com"),
            auth.replacingOccurrences(of: "buy.itunes.apple.com", with: "user:password@buy.itunes.apple.com"),
            auth.replacingOccurrences(of: "buy.itunes.apple.com", with: "buy.itunes.apple.com:8080"),
            auth.replacingOccurrences(of: "/wa/authenticate", with: "/wa/buyProduct"),
            auth + "#fragment",
        ] {
            do {
                _ = try StoreAuthenticationProtocol.authenticationURL(invalid)
                fatalError("Accepted an unsafe credential redirect")
            } catch is StoreAuthenticationError {}
        }
        precondition(StoreAuthenticationProtocol.storeIdentifier("143441-1,29") == "143441")
        precondition(StoreAuthenticationProtocol.storeIdentifier("143465-19,32") == "143465")
        // Login's Foundation cookie jar and ApplePackage use different domain forms.
        let cookie = HTTPCookie(properties: [
            .name: "synthetic-session", .value: "fixture", .domain: ".itunes.apple.com",
            .path: "/WebObjects/", .secure: "TRUE",
        ])!
        precondition(StoreProtocol.storeCookieDomain(cookie.domain) == "itunes.apple.com")
        precondition(StoreProtocol.storeCookieDomain(".P25-BUY.ITUNES.APPLE.COM") == "p25-buy.itunes.apple.com")
        precondition(StoreProtocol.storeCookieDomain(nil) == nil)
        precondition(StoreProtocol.storeCookieDomain(".") == "")
        for invalid in [nil, "", ".", "attacker.example", "itunes.apple.com.attacker.example"] as [String?] {
            precondition(StoreProtocol.foundationCookieDomain(invalid) == nil)
        }
        let restored = HTTPCookie(properties: [
            .name: cookie.name, .value: cookie.value, .path: cookie.path, .secure: "TRUE",
            .domain: StoreProtocol.foundationCookieDomain("itunes.apple.com")!,
        ])!
        let jar = URLSessionConfiguration.ephemeral.httpCookieStorage!
        jar.setCookie(restored)
        precondition(jar.cookies(for: URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct")!)?.contains(where: { $0.name == cookie.name }) == true)
        for url in ["http://p25-buy.itunes.apple.com/WebObjects/", "https://p25-buy.itunes.apple.com/other/", "https://attacker.example/WebObjects/"] {
            precondition(jar.cookies(for: URL(string: url)!)?.contains(where: { $0.name == cookie.name }) != true)
        }
        let body = try StoreAuthenticationProtocol.body(email: "test@example.invalid", password: "&<测试>", code: " 123 456\n", guid: "024153535050", attempt: 1)
        let plist = StoreProtocol.plist(body)!
        precondition(plist["password"] as? String == "&<测试>123456")
        precondition(plist["attempt"] as? String == "1")
        precondition(plist["guid"] as? String == "024153535050")
        let wrapped = Data(("<Document><Protocol>" + String(data: body, encoding: .utf8)! + "</Protocol></Document>").utf8)
        precondition(StoreProtocol.plist(wrapped)?["guid"] as? String == "024153535050")
        let binary = try PropertyListSerialization.data(fromPropertyList: ["failureType": "5005"], format: .binary, options: 0)
        precondition(StoreProtocol.plist(binary)?["failureType"] as? String == "5005")
        precondition(StoreAuthenticationProtocol.rejection(["customerMessage": "MZFinance.BadLogin.Configurator_message"], code: "")?.needsCode == true)
        precondition(StoreAuthenticationProtocol.rejection(["failureType": 5005], code: "123456")?.needsCode == true)
        precondition(StoreAuthenticationProtocol.rejection(["failureType": "-5000", "customerMessage": "Bad credentials"], code: "")?.needsCode == false)
        precondition(StoreAuthenticationError.serviceResponse(403).needsCode == false)
        for status in [204, 404, 500, 503] {
            precondition(StoreAuthenticationProtocol.retryable(status: status, data: Data()))
        }
        for status in [200, 301, 302, 400, 401, 403, 429] {
            precondition(!StoreAuthenticationProtocol.retryable(status: status, data: Data()))
        }
        // Never retry a parsed rejection even when the HTTP layer says 5xx.
        precondition(!StoreAuthenticationProtocol.retryable(status: 500, data: binary))
        print("Authentication protocol regression checks passed.")
    }
}
