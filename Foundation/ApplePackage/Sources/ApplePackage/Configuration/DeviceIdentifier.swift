//
//  DeviceIdentifier.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

public enum DeviceIdentifier {
    public static func system() throws -> String {
        #if os(iOS)
            // https://developer.apple.com/library/archive/releasenotes/General/WhatsNewIniOS/Articles/iOS7.html#:~:text=returns%20the%20value-,02:00:00:00:00:00,-.%20If%20you%20need
            try ensureFailed("will always return: 02:00:00:00:00:00")
        #else
            let MAC_ADDRESS_LENGTH = 6
            let bsds: [String] = ["en0", "en1"]
            var bsd: String = bsds[0]

            var length: size_t = 0
            var buffer: [CChar]

            var bsdIndex = Int32(if_nametoindex(bsd))
            if bsdIndex == 0 {
                bsd = bsds[1]
                bsdIndex = Int32(if_nametoindex(bsd))
                guard bsdIndex != 0 else { try ensureFailed("unable to get interface") }
            }

            let bsdData = Data(bsd.utf8)
            var managementInfoBase = [CTL_NET, AF_ROUTE, 0, AF_LINK, NET_RT_IFLIST, bsdIndex]

            guard sysctl(&managementInfoBase, 6, nil, &length, nil, 0) >= 0 else {
                try ensureFailed("unable to get interface info")
            }

            buffer = [CChar](unsafeUninitializedCapacity: length, initializingWith: { buffer, initializedCount in
                for x in 0 ..< length {
                    buffer[x] = 0
                }
                initializedCount = length
            })

            guard sysctl(&managementInfoBase, 6, &buffer, &length, nil, 0) >= 0 else {
                try ensureFailed("unable to get interface info")
            }

            let infoData = Data(bytes: buffer, count: length)
            let indexAfterMsghdr = MemoryLayout<if_msghdr>.stride + 1
            let rangeOfToken = infoData[indexAfterMsghdr...].range(of: bsdData)!
            let lower = rangeOfToken.upperBound
            let upper = lower + MAC_ADDRESS_LENGTH
            let macAddressData = infoData[lower ..< upper]
            let addressBytes = macAddressData.map { String(format: "%02x", $0) }
            let result = addressBytes.joined().uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            try ensure(!result.isEmpty, "unable to get mac address")

            return result
        #endif
    }

    public static func random() -> String {
        let chars = [
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "A", "B", "C", "D", "E", "F",
        ]
        var ans = ""
        while ans.count < 12 {
            ans.append(chars.randomElement()!)
        }
        return ans
    }
}
