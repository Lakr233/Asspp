//
//  DiggerSeed.swift
//  Digger
//
//  Created by ant on 2017/10/28.
//  Copyright © 2017年 github.cornerant. All rights reserved.
//

import Foundation

public typealias ProgressCallback = (_ progress: Progress) -> Void

public typealias SpeedCallback = (_ speedBytes: Int64) -> Void

public typealias CompletionCallback = (_ completion: Result<URL>) -> Void

public typealias Callback = (progress: ProgressCallback?, speed: SpeedCallback?, completion: CompletionCallback?)

public class DiggerSeed {
    var downloadTask: URLSessionDataTask
    var url: URL
    var progress = Progress()
    var callbacks = [Callback]()
    var cancelSemaphore: DispatchSemaphore?
    var tempPath: String {
        DiggerCache.tempPath(url: url)
    }

    var cachePath: String {
        DiggerCache.cachePath(url: url)
    }

    var cacheFileURL: URL {
        URL(fileURLWithPath: DiggerCache.cachePath(url: url))
    }

    var outputStream: OutputStream?

    init(session: URLSession, url: URL, timeout: TimeInterval) {
        downloadTask = session.dataTask(with: url, timeout: timeout)
        self.url = url
    }

    /// downloading progress
    ///
    /// - Parameter progress: progress
    /// - Returns: DiggerSeed
    @discardableResult
    public func progress(_ progress: @escaping ProgressCallback) -> Self {
        var callback = Callback(nil, nil, nil)
        callback.progress = progress
        callbacks.append(callback)

        return self
    }

    /// downloading speed
    ///
    /// - Parameter speed: downloading speed, Unit: Bytes
    /// - Returns: DiggerSeed
    @discardableResult
    public func speed(_ speed: @escaping SpeedCallback) -> Self {
        var callback = Callback(nil, nil, nil)
        callback.speed = speed
        callbacks.append(callback)

        return self
    }

    /// download result
    ///
    /// - Parameter completion: Restult
    /// - Returns: DiggerSeed
    @discardableResult
    public func completion(_ completion: @escaping CompletionCallback) -> Self {
        var callback = Callback(nil, nil, nil)
        callback.completion = completion
        callbacks.append(callback)

        return self
    }
}
