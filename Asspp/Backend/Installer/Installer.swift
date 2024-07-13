//
//  Installer.swift
//  AppInstaller
//
//  Created by 秋星桥 on 2024/7/10.
//

import ApplePackage
import Logging
import UIKit
import Vapor

class Installer: Identifiable, ObservableObject {
    let id: UUID
    let app: Application
    let archive: iTunesResponse.iTunesArchive
    let port = Int.random(in: 4000 ... 8000)

    enum Status {
        case ready
        case sendingManifest
        case sendingPayload
        case completed(Result<Void, Error>)
        case broken(Error)
    }

    @Published var status: Status = .ready

    var needsShutdown = false

    init(archive: iTunesResponse.iTunesArchive, path packagePath: URL) throws {
        let id: UUID = .init()
        self.id = id
        self.archive = archive
        app = try Self.setupApp(port: port)

        app.get("*") { [weak self] req in
            guard let self else { return Response(status: .badGateway) }

            switch req.url.path {
            case "/ping":
                return Response(status: .ok, body: .init(string: "pong"))
            case "/", "/index.html":
                return Response(status: .ok, version: req.version, headers: [
                    "Content-Type": "text/html",
                ], body: .init(string: indexHtml))
            case plistEndpoint.path:
                DispatchQueue.main.async { self.status = .sendingManifest }
                return Response(status: .ok, version: req.version, headers: [
                    "Content-Type": "text/xml",
                ], body: .init(data: installManifestData))
            case displayImageSmallEndpoint.path:
                DispatchQueue.main.async { self.status = .sendingManifest }
                return Response(status: .ok, version: req.version, headers: [
                    "Content-Type": "image/png",
                ], body: .init(data: displayImageSmallData))
            case displayImageLargeEndpoint.path:
                DispatchQueue.main.async { self.status = .sendingManifest }
                return Response(status: .ok, version: req.version, headers: [
                    "Content-Type": "image/png",
                ], body: .init(data: displayImageLargeData))
            case payloadEndpoint.path:
                DispatchQueue.main.async { self.status = .sendingPayload }
                return req.fileio.streamFile(
                    at: packagePath.path
                ) { result in
                    DispatchQueue.main.async { self.status = .completed(result) }
                }
            default:
                // 404
                return Response(status: .notFound)
            }
        }

        try app.server.start()
        needsShutdown = true
        print("[*] installer init at port \(port) for sni \(Self.sni)")
    }

    deinit {
        destroy()
    }

    func destroy() {
        print("[*] installer destroy")
        if needsShutdown {
            needsShutdown = false
            app.server.shutdown()
            app.shutdown()
        }
    }
}
