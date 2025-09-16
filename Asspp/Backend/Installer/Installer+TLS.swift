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
    static let sni = "app.localhost.qaq.wiki"
    static let pem = Bundle.main.url(
        forResource: "localhost.qaq.wiki-key",
        withExtension: "pem",
        subdirectory: "Certificates/localhost.qaq.wiki"
    )
    static let crt = Bundle.main.url(
        forResource: "localhost.qaq.wiki",
        withExtension: "pem",
        subdirectory: "Certificates/localhost.qaq.wiki"
    )
    static let ca = Bundle.main.url(
        forResource: "rootCA",
        withExtension: "pem",
        subdirectory: "Certificates/localhost.qaq.wiki"
    )!

    static var caURL: URL = .init(fileURLWithPath: "/tmp/")
    static var caInstaller: Installer?

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
            privateKey: NIOSSLPrivateKeySource.privateKey(NIOSSLPrivateKey(file: pem.path, format: .pem))
        )
    }
}
