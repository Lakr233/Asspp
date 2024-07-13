//
//  Installer+TLS.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import Foundation
import NIOSSL
import NIOTLS
import Vapor

extension Installer {
    static let sni = "app.localhost.direct"
    static let pem = Bundle.main.url(
        forResource: "localhost.direct",
        withExtension: "pem",
        subdirectory: "Certificates/localhost.direct"
    )
    static let crt = Bundle.main.url(
        forResource: "localhost.direct",
        withExtension: "crt",
        subdirectory: "Certificates/localhost.direct"
    )

    static func setupTLS() throws -> TLSConfiguration {
        guard let crt, let pem else {
            throw NSError(domain: "Installer", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load ssl certificates",
            ])
        }
        return try TLSConfiguration.makeServerConfiguration(
            certificateChain: NIOSSLCertificate
                .fromPEMFile(crt.path)
                .map { NIOSSLCertificateSource.certificate($0) },
            privateKey: .file(pem.path)
        )
    }
}
