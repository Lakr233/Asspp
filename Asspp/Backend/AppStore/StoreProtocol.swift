import Foundation

/// Serialization and cookie conventions shared by store authentication and product requests.
enum StoreProtocol {
    static func plist(_ data: Data) -> [String: Any]? {
        var payload = data
        // bag.xml wraps a plist in Document/Protocol; login replies are ordinary plists.
        if let xml = String(data: data, encoding: .utf8),
           let start = xml.range(of: "<plist"), let end = xml.range(of: "</plist>"),
           start.lowerBound < end.upperBound
        {
            payload = Data(xml[start.lowerBound ..< end.upperBound].utf8)
        }
        return (try? PropertyListSerialization.propertyList(from: payload, format: nil)) as? [String: Any]
    }

    static func storeCookieDomain(_ domain: String?) -> String? {
        domain.map { String($0.drop(while: { $0 == "." })).lowercased() }
    }

    static func foundationCookieDomain(_ domain: String?) -> String? {
        guard let domain = storeCookieDomain(domain),
              domain == "itunes.apple.com" || domain.hasSuffix(".itunes.apple.com")
        else { return nil }
        return "." + domain
    }

    static func string(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }
}
