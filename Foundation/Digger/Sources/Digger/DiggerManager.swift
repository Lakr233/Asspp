

//
//  DiggerManager.swift
//  Digger
//
//  Created by ant on 2017/10/25.
//  Copyright © 2017年 github.cornerant. All rights reserved.
//

import Foundation

public protocol DiggerManagerProtocol {
    /// logLevel hing,low,none
    var logLevel: LogLevel { set get }

    /// Apple limit is per session,The default value is 6 in macOS, or 4 in iOS.
    var maxConcurrentTasksCount: Int { set get }

    var allowsCellularAccess: Bool { set get }

    var additionalHTTPHeaders: [String: String] { set get }

    var timeout: TimeInterval { set get }

    /// Start the task at once,default is true

    var startDownloadImmediately: Bool { set get }

    func startTask(for diggerURL: DiggerURL)

    func stopTask(for diggerURL: DiggerURL)

    /// If the task is cancelled, the temporary file will be deleted
    func cancelTask(for diggerURL: DiggerURL)

    func startAllTasks()

    func stopAllTasks()

    func cancelAllTasks()
}

open class DiggerManager: DiggerManagerProtocol {
    // MARK: -  property

    public static var shared = DiggerManager(name: digger)
    public var logLevel: LogLevel = .high
    open var startDownloadImmediately = true
    open var timeout: TimeInterval = 100
    fileprivate var diggerSeeds = [URL: DiggerSeed]()
    fileprivate var session: URLSession
    fileprivate var diggerDelegate: DiggerDelegate?
    fileprivate let barrierQueue = DispatchQueue.barrier
    fileprivate let delegateQueue = OperationQueue.downloadDelegateOperationQueue
    private let accessLock = NSLock()

    public var maxConcurrentTasksCount: Int = 3 {
        didSet {
            let count = maxConcurrentTasksCount == 0 ? 1 : maxConcurrentTasksCount
            session.invalidateAndCancel()
            session = setupSession(allowsCellularAccess, count, additionalHTTPHeaders)
        }
    }

    public var allowsCellularAccess: Bool = true {
        didSet {
            session.invalidateAndCancel()
            session = setupSession(allowsCellularAccess, maxConcurrentTasksCount, additionalHTTPHeaders)
        }
    }

    public var additionalHTTPHeaders: [String: String] = [:] {
        didSet {
            session.invalidateAndCancel()
            session = setupSession(allowsCellularAccess, maxConcurrentTasksCount, additionalHTTPHeaders)
        }
    }

    // MARK: -  lifeCycle

    private init(name: String) {
        DiggerCache.cachesDirectory = digger
        if name.isEmpty {
            fatalError("DiggerManager must hava a name")
        }

        diggerDelegate = DiggerDelegate()
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.allowsCellularAccess = allowsCellularAccess
        sessionConfiguration.httpMaximumConnectionsPerHost = maxConcurrentTasksCount
        sessionConfiguration.httpAdditionalHeaders = additionalHTTPHeaders
        session = URLSession(configuration: sessionConfiguration, delegate: diggerDelegate, delegateQueue: delegateQueue)
    }

    deinit {
        session.invalidateAndCancel()
    }

    private func setupSession(_ allowsCellularAccess: Bool, _ maxDownloadTasksCount: Int, _ additionalHTTPHeaders: [String: String]) -> URLSession {
        diggerDelegate = DiggerDelegate()
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.allowsCellularAccess = allowsCellularAccess
        sessionConfiguration.httpMaximumConnectionsPerHost = maxDownloadTasksCount
        sessionConfiguration.httpAdditionalHeaders = additionalHTTPHeaders
        let session = URLSession(configuration: sessionConfiguration, delegate: diggerDelegate, delegateQueue: delegateQueue)

        return session
    }

    ///  download file
    ///  DiggerSeed contains information about the file
    /// - Parameter diggerURL: url
    /// - Returns: the diggerSeed of file
    @discardableResult
    public func download(with diggerURL: DiggerURL) -> DiggerSeed {
        switch isDiggerURLCorrect(diggerURL) {
        case let .success(url):
            createDiggerSeed(with: url)
        case .failure:
            fatalError("Please make sure the url or urlString is correct")
        }
    }
}

// MARK: -  diggerSeed control

extension DiggerManager {
    func createDiggerSeed(with url: URL) -> DiggerSeed {
        if let seed = findDiggerSeed(with: url) {
            return seed
        } else {
            barrierQueue.sync(flags: .barrier) {
                let timeout = self.timeout == 0.0 ? 100 : self.timeout
                let diggerSeed = DiggerSeed(session: session, url: url, timeout: timeout)
                diggerSeeds[url] = diggerSeed
            }

            let diggerSeed = findDiggerSeed(with: url)!
            diggerDelegate?.manager = self
            if startDownloadImmediately {
                diggerSeed.downloadTask.resume()
            }
            return diggerSeed
        }
    }

    public func removeDigeerSeed(for url: URL) {
        barrierQueue.sync(flags: .barrier) {
            diggerSeeds.removeValue(forKey: url)
            if diggerSeeds.isEmpty { diggerDelegate = nil }
        }
    }

    func isDiggerURLCorrect(_ diggerURL: DiggerURL) -> Result<URL> {
        var correctURL: URL
        do {
            correctURL = try diggerURL.asURL()
            return Result.success(correctURL)
        } catch {
            diggerLog(error)
            return Result.failure(error)
        }
    }

    func findDiggerSeed(with diggerURL: DiggerURL) -> DiggerSeed? {
        var diggerSeed: DiggerSeed?
        switch isDiggerURLCorrect(diggerURL) {
        case let .success(url):
            barrierQueue.sync(flags: .barrier) { diggerSeed = diggerSeeds[url] }
            return diggerSeed
        case .failure:
            return diggerSeed
        }
    }
}

// MARK: -  downloadTask control

public extension DiggerManager {
    func cancelTask(for diggerURL: DiggerURL) {
        switch isDiggerURLCorrect(diggerURL) {
        case .failure: return
        case let .success(url):
            barrierQueue.sync(flags: .barrier) {
                guard let diggerSeed = diggerSeeds[url] else { return }
                diggerSeed.downloadTask.cancel()
            }
        }
    }

    func stopTask(for diggerURL: DiggerURL) {
        switch isDiggerURLCorrect(diggerURL) {
        case .failure: return
        case let .success(url):
            barrierQueue.sync(flags: .barrier) {
                guard let diggerSeed = diggerSeeds[url] else { return }
                if diggerSeed.downloadTask.state == .running {
                    diggerSeed.downloadTask.suspend()
                    diggerDelegate?.notifySpeedZeroCallback(diggerSeed)
                }
            }
        }
    }

    func startTask(for diggerURL: DiggerURL) {
        switch isDiggerURLCorrect(diggerURL) {
        case .failure: return
        case let .success(url):
            barrierQueue.sync(flags: .barrier) {
                guard let diggerSeed = diggerSeeds[url] else { return }
                if diggerSeed.downloadTask.state != .running {
                    diggerSeed.downloadTask.resume()
                    self.diggerDelegate?.notifySpeedCallback(diggerSeed)
                }
            }
        }
    }

    func startAllTasks() {
        accessLock.lock()
        let fetch = diggerSeeds
        accessLock.unlock()
        fetch.keys.forEach { startTask(for: $0) }
    }

    func stopAllTasks() {
        accessLock.lock()
        let fetch = diggerSeeds
        accessLock.unlock()
        fetch.keys.forEach { stopTask(for: $0) }
    }

    func cancelAllTasks() {
        accessLock.lock()
        let fetch = diggerSeeds
        accessLock.unlock()
        fetch.keys.forEach { cancelTask(for: $0) }
    }

    func obtainAllTasks() -> [URL] {
        accessLock.lock()
        let result = [URL](diggerSeeds.keys)
        accessLock.unlock()
        return result
    }
}

// MARK: -  URLSessionExtension

public extension URLSession {
    func dataTask(with url: URL, timeout: TimeInterval) -> URLSessionDataTask {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        let range = DiggerCache.fileSize(filePath: DiggerCache.tempPath(url: url))
        if range > 0 {
            if isContentRangeSupportedOn(url: url, timeout: timeout) {
                let headRange = "bytes=" + String(range) + "-"
                request.setValue(headRange, forHTTPHeaderField: "Range")
            } else {
                DiggerCache.removeTempFile(with: url)
            }
        }
        let task = dataTask(with: request)
        task.priority = URLSessionTask.defaultPriority
        return task
    }

    func isContentRangeSupportedOn(url: URL, timeout: TimeInterval) -> Bool {
        var preflightCheck = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        preflightCheck.httpMethod = "HEAD"
        var supportRange = false
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: preflightCheck) { _, resp, _ in
            if let httpResponse = resp as? HTTPURLResponse {
                for (key, value) in httpResponse.allHeaderFields {
                    if let keyStr = key as? String, keyStr.lowercased() == "accept-ranges" {
                        supportRange = (value as? String)?.lowercased() != "none"
                    }
                }
            }
            sem.signal()
        }.resume()
        sem.wait()
        return supportRange
    }
}
