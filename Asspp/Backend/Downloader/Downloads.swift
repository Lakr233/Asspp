//
//  Downloads.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

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

    // Manifest IDs whose Digger callbacks are already attached, so a
    // pause/resume cycle does not register a second completion handler (which
    // would run finalize() twice and destroy the downloaded bytes).
    @ObservationIgnored
    private var registeredCallbacks: Set<UUID> = []

    private static let speedFormatter: ByteCountFormatter = {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file
        return fmt
    }()

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

    // Stored, not computed: a computed property would read each manifest's
    // `state`, so every download progress tick would invalidate the badge,
    // sidebar, and AppDelegate observers and re-render the whole TabView.
    // Refresh it only when a status actually transitions.
    private(set) var runningTaskCount: Int = 0

    private func refreshRunningTaskCount() {
        runningTaskCount = manifests.count(where: { $0.state.status == .downloading })
    }

    private init() {
        for idx in manifests.indices {
            manifests[idx].state.resetIfNotCompleted()
        }
        refreshRunningTaskCount()
    }

    func saveManifests() {
        _manifests.save()
    }

    func downloadRequest(forArchive archive: AppStore.AppPackage) -> PackageManifest? {
        manifests.first {
            $0.package.id == archive.id
                && $0.package.externalVersionID == archive.externalVersionID
                && $0.package.entityType == archive.entityType
        }
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
        refreshRunningTaskCount()
        saveManifests()
    }

    func resume(request: PackageManifest) {
        logger.info("resuming download request id: \(request.id)")
        request.state.start()
        let seed = DiggerManager.shared.download(with: request.url)

        // Only attach callbacks once per manifest; a pause/resume cycle reuses
        // the existing Digger seed and must not stack a second completion.
        guard registeredCallbacks.insert(request.id).inserted else {
            DiggerManager.shared.startTask(for: request.url)
            saveManifests()
            return
        }

        seed
            .speed { speedBytes in
                Task { @MainActor in
                    guard request.state.status == .downloading || request.state.status == .pending else { return }
                    let wasDownloading = request.state.status == .downloading
                    var newState = request.state
                    newState.status = .downloading
                    newState.speed = Self.speedFormatter.string(fromByteCount: Int64(speedBytes))
                    request.state = newState
                    if !wasDownloading { self.refreshRunningTaskCount() }
                }
            }
            .progress { progress in
                Task { @MainActor in
                    guard request.state.status == .downloading || request.state.status == .pending else { return }
                    let now = CFAbsoluteTimeGetCurrent()
                    let fraction = progress.fractionCompleted
                    let last = self.lastProgressUpdates[request.id] ?? 0
                    guard fraction >= 1.0 || (now - last) >= 0.2 else { return }
                    self.lastProgressUpdates[request.id] = now

                    let wasDownloading = request.state.status == .downloading
                    var newState = request.state
                    newState.status = .downloading
                    newState.percent = fraction
                    request.state = newState
                    if !wasDownloading { self.refreshRunningTaskCount() }
                }
            }
            .completion { completion in
                Task { @MainActor in
                    self.registeredCallbacks.remove(request.id)
                    switch completion {
                    case let .success(url):
                        Task.detached {
                            do {
                                try await self.finalize(manifest: request, preparedContentAt: url)
                                await MainActor.run {
                                    request.state.complete()
                                    self.refreshRunningTaskCount()
                                    self.saveManifests()
                                }
                            } catch {
                                await MainActor.run {
                                    request.state.error = error.localizedDescription
                                    self.refreshRunningTaskCount()
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
                        self.refreshRunningTaskCount()
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
        registeredCallbacks.remove(request.id)
        request.delete()
        manifests.removeAll(where: { $0.id == request.id })
        refreshRunningTaskCount()
    }

    func restart(request: PackageManifest) {
        logger.info("restarting download request id: \(request.id)")
        DiggerManager.shared.cancelTask(for: request.url)
        registeredCallbacks.remove(request.id)
        request.delete()
        request.state = .init()
        resume(request: request)
    }

    func removeAll() {
        manifests.forEach { $0.delete() }
        manifests.removeAll()
        registeredCallbacks.removeAll()
        refreshRunningTaskCount()
    }
}
