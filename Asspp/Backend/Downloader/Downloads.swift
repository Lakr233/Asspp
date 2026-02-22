//
//  Downloads.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import AnyCodable
import ApplePackage
@preconcurrency import Digger
import Foundation
import Logging

@Observable
@MainActor
class Downloads {
    static let this = Downloads()

    @ObservationIgnored
    private var _manifests = Persist<[PackageManifest]>(key: "DownloadRequests", defaultValue: [])

    @ObservationIgnored
    private var lastProgressUpdates: [UUID: CFAbsoluteTime] = [:]

    var manifests: [PackageManifest] {
        get {
            access(keyPath: \.manifests)
            return _manifests.wrappedValue
        }
        set {
            withMutation(keyPath: \.manifests) {
                _manifests.wrappedValue = newValue
            }
        }
    }

    var runningTaskCount: Int {
        manifests.count(where: { $0.state.status == .downloading })
    }

    init() {
        for idx in manifests.indices {
            manifests[idx].state.resetIfNotCompleted()
        }
    }

    func saveManifests() {
        _manifests.save()
    }

    func downloadRequest(forArchive archive: AppStore.AppPackage) -> PackageManifest? {
        manifests.first { $0.package.id == archive.id && $0.package.externalVersionID == archive.externalVersionID }
    }

    func add(request: PackageManifest) -> PackageManifest {
        logger.info("adding download request \(request.id) - \(request.package.software.name)")
        manifests.removeAll { $0.id == request.id }
        manifests.append(request)
        return request
    }

    func suspend(request: PackageManifest) {
        logger.info("suspending download request id: \(request.id)")
        DiggerManager.shared.stopTask(for: request.url)
        request.state.resetIfNotCompleted()
        saveManifests()
    }

    func resume(request: PackageManifest) {
        logger.info("resuming download request id: \(request.id)")
        request.state.start()
        DiggerManager.shared.download(with: request.url)
            .speed { speedBytes in
                Task { @MainActor in
                    let fmt = ByteCountFormatter()
                    fmt.allowedUnits = .useAll
                    fmt.countStyle = .file
                    var newState = request.state
                    newState.status = .downloading
                    newState.speed = fmt.string(fromByteCount: Int64(speedBytes))
                    request.state = newState
                }
            }
            .progress { progress in
                Task { @MainActor in
                    let now = CFAbsoluteTimeGetCurrent()
                    let fraction = progress.fractionCompleted
                    let last = self.lastProgressUpdates[request.id] ?? 0
                    guard fraction >= 1.0 || (now - last) >= 0.2 else { return }
                    self.lastProgressUpdates[request.id] = now

                    var newState = request.state
                    newState.status = .downloading
                    newState.percent = fraction
                    request.state = newState
                }
            }
            .completion { completion in
                Task { @MainActor in
                    switch completion {
                    case let .success(url):
                        Task.detached {
                            do {
                                try await self.finalize(manifest: request, preparedContentAt: url)
                                await MainActor.run {
                                    request.state.complete()
                                    self.saveManifests()
                                }
                            } catch {
                                await MainActor.run {
                                    request.state.error = error.localizedDescription
                                    self.saveManifests()
                                }
                            }
                        }
                    case let .failure(error):
                        let nsError = error as NSError
                        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                            // User-initiated cancellation via cancelTask(), not an error
                        } else if error is CancellationError {
                            // Swift structured concurrency cancellation
                        } else {
                            request.state.error = error.localizedDescription
                            self.saveManifests()
                        }
                    }
                }
            }
        DiggerManager.shared.startTask(for: request.url)
        saveManifests()
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

        logger.info("injecting signatures: \(manifest.id)")
        try await SignatureInjector.inject(
            sinfs: manifest.signatures,
            iTunesMetadata: manifest.iTunesMetadata,
            into: tempFile.path,
        )

        logger.info("moving finalized file: \(manifest.id)")
        try FileManager.default.moveItem(at: tempFile, to: manifest.targetLocation)
    }

    func delete(request: PackageManifest) {
        logger.info("deleting download request id: \(request.id)")
        DiggerManager.shared.cancelTask(for: request.url)
        request.delete()
        manifests.removeAll(where: { $0.id == request.id })
    }

    func restart(request: PackageManifest) {
        logger.info("restarting download request id: \(request.id)")
        DiggerManager.shared.cancelTask(for: request.url)
        request.delete()
        request.state = .init()
        resume(request: request)
    }

    func removeAll() {
        manifests.forEach { $0.delete() }
        manifests.removeAll()
    }
}
