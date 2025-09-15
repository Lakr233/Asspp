//
//  Downloads.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import AnyCodable
import ApplePackage
import Combine
@preconcurrency import Digger
import Foundation
import Logging

@MainActor
class Downloads: NSObject, ObservableObject {
    static let this = Downloads()

    @PublishedPersist(key: "DownloadRequests", defaultValue: [])
    var manifests: [PackageManifest] {
        didSet { updateSaver() }
    }

    private var manifestSaver: Set<AnyCancellable> = []

    var runningTaskCount: Int {
        manifests.count(where: { $0.state.status == .downloading })
    }

    override init() {
        super.init()
        for idx in manifests.indices {
            manifests[idx].state.resetIfNotCompleted()
        }
        updateSaver()
    }

    private func updateSaver() {
        manifestSaver.forEach { $0.cancel() }
        manifestSaver.removeAll()
        manifestSaver = Set(manifests.map { manifest in
            manifest.objectWillChange.sink { [weak self] in
                self?.objectWillChange.send()
            }
        })
        objectWillChange
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
                guard let self else { return }
                _manifests.save()
            }
            .store(in: &manifestSaver)
    }

    func downloadRequest(forArchive archive: AppStore.AppPackage) -> PackageManifest? {
        manifests.first { $0.package.id == archive.id && $0.package.externalVersionID == archive.externalVersionID }
    }

    func add(request: PackageManifest) -> PackageManifest {
        logger.info("adding download request \(request.id)")
        manifests.removeAll { $0.id == request.id }
        manifests.append(request)
        return request
    }

    func suspend(request: PackageManifest) {
        logger.info("suspending download request id: \(request)")
        DiggerManager.shared.cancelTask(for: request.url)
        request.state.resetIfNotCompleted()
    }

    func resume(request: PackageManifest) {
        logger.info("resuming download request id: \(request)")
        request.state.start()
        DiggerManager.shared.download(with: request.url)
            .speed { speedBytes in
                DispatchQueue.main.async {
                    let fmt = ByteCountFormatter()
                    fmt.allowedUnits = .useAll
                    fmt.countStyle = .file
                    request.state.status = .downloading
                    request.state.speed = fmt.string(fromByteCount: Int64(speedBytes))
                }
            }
            .progress { progress in
                DispatchQueue.main.async {
                    request.state.status = .downloading
                    request.state.percent = progress.fractionCompleted
                }
            }
            .completion { completion in
                DispatchQueue.main.async {
                    switch completion {
                    case let .success(url):
                        Task.detached {
                            do {
                                try await self.finalize(manifest: request, preparedContentAt: url)
                                await MainActor.run {
                                    request.state.complete()
                                }
                            } catch {
                                await MainActor.run {
                                    request.state.error = error.localizedDescription
                                }
                            }
                        }
                    case let .failure(error):
                        if error is CancellationError {
                            // not an error at all
                        } else {
                            request.state.error = error.localizedDescription
                        }
                    }
                }
            }
    }

    private func finalize(manifest: PackageManifest, preparedContentAt downloadedFile: URL) async throws {
        try? FileManager.default.createDirectory(
            at: manifest.targetLocation.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? FileManager.default.removeItem(at: manifest.targetLocation)

        let tempFile = manifest.targetLocation
            .deletingLastPathComponent()
            .appendingPathComponent(".\(manifest.targetLocation.lastPathComponent).unsigned")
        try? FileManager.default.removeItem(at: tempFile)

        logger.info("preparing signature: \(manifest.id)")
        try FileManager.default.moveItem(at: downloadedFile, to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        logger.info("injecting signatures:\(manifest.id)")
        try await SignatureInjector.inject(sinfs: manifest.signatures, into: tempFile.path)

        logger.info("moving finalized file: \(manifest.id)")
        try FileManager.default.moveItem(at: tempFile, to: manifest.targetLocation)
    }

    func delete(request: PackageManifest) {
        logger.info("deleting download request id: \(request)")
        suspend(request: request)
        request.delete()
        manifests.removeAll(where: { $0.id == request.id })
    }

    func restart(request: PackageManifest) {
        logger.info("restarting download request id: \(request.id)")
        suspend(request: request)
        request.delete()
        request.state.resetIfNotCompleted()
        resume(request: request)
    }

    func removeAll() {
        manifests.forEach { $0.delete() }
        manifests.removeAll()
    }
}
