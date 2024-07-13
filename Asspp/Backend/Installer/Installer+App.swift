//
//  Installer+App.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import Foundation
import Vapor

extension Installer {
    private static let env: Environment = {
        var env = try! Environment.detect()
        try! LoggingSystem.bootstrap(from: &env)
        return env
    }()

    static func setupApp(port: Int) throws -> Application {
        let app = Application(env)

        app.threadPool = .init(numberOfThreads: 1)

        app.http.server.configuration.tlsConfiguration = try Self.setupTLS()
        app.http.server.configuration.hostname = Self.sni
        app.http.server.configuration.tcpNoDelay = true

        app.http.server.configuration.address = .hostname("0.0.0.0", port: port)
        app.http.server.configuration.port = port

        app.routes.defaultMaxBodySize = "128mb"
        app.routes.caseInsensitive = false

        return app
    }
}
