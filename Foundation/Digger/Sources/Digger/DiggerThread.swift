//
//  DiggerThread.swift
//  Digger
//
//  Created by ant on 2017/10/27.
//  Copyright © 2017年 github.cornerant. All rights reserved.
//

import Foundation

extension DispatchQueue {
    static let barrier = DispatchQueue(label: "wiki.qaq.diggerThread.Barrier", attributes: .concurrent)
    static let cancel = DispatchQueue(label: "wiki.qaq.diggerThread.cancel", attributes: .concurrent)
    static let download = DispatchQueue(label: "wiki.qaq.downloadSession.download", attributes: .concurrent)
    static let forFun = DispatchQueue(label: "wiki.qaq.diggerThread.forFun", attributes: .concurrent)

    func safeAsync(_ block: @escaping () -> Void) {
        if self === DispatchQueue.main, Thread.isMainThread {
            block()
        } else {
            async { block() }
        }
    }
}

extension OperationQueue {
    static var downloadDelegateOperationQueue: OperationQueue {
        let downloadDelegateOperationQueue = OperationQueue()
        downloadDelegateOperationQueue.name = "wiki.qaq.diggerThread.downloadDelegateOperationQueue"
        return downloadDelegateOperationQueue
    }
}
