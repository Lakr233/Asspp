//
//  Downloads+Report.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import Foundation

extension Downloads {
    func alter(reqID: Request.ID, _ callback: @escaping (inout Request) -> Void) {
        DispatchQueue.main.async { [self] in
            guard let index = requests.firstIndex(where: { $0.id == reqID }) else { return }
            var req = requests[index]
            let deduplicate = req
            callback(&req)
            guard deduplicate != req else { return }
            requests[index] = req
        }
    }

    func reportValidating(reqId: Request.ID) {
        alter(reqID: reqId) { req in
            req.runtime.status = .verifying
        }
    }

    func reportSuccess(reqId: Request.ID) {
        alter(reqID: reqId) { req in
            req.runtime.status = .completed
            req.runtime.percent = 1
            req.runtime.error = nil
        }
    }

    func report(error: Error?, reqId: Request.ID) {
        print(Thread.callStackSymbols.joined(separator: "\n"))
        let error = error ?? NSError(domain: "DownloadManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Unknown error",
        ])
        alter(reqID: reqId) { req in
            req.runtime.error = error.localizedDescription
            req.runtime.status = .stopped
        }
    }

    func report(progress: Progress, reqId: Request.ID) {
        alter(reqID: reqId) { req in
            req.runtime.percent = progress.fractionCompleted
            req.runtime.status = .downloading
            req.runtime.error = nil
        }
    }

    func report(speed: String, reqId: Request.ID) {
        alter(reqID: reqId) { req in
            req.runtime.speed = speed
            req.runtime.status = .downloading
            req.runtime.error = nil
        }
    }
}
