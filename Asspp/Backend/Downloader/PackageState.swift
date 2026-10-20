//
//  PackageState.swift
//  Asspp
//
//  Created by qaq on 9/15/25.
//

import Foundation

struct PackageState: Codable, Hashable, Equatable {
    enum Status: String, Codable, Equatable, Hashable {
        case pending
        case downloading
        case paused
        case completed
        case failed
    }

    var status: Status = .pending
    var percent: Double = 0 {
        didSet { assert(percent >= 0 && percent <= 1) }
    }

    var error: String? = nil {
        didSet {
            if error != nil {
                status = .failed
            }
        }
    }

    var speed: String = ""
}

extension PackageState {
    mutating func start() {
        status = .pending
        error = nil
    }

    mutating func resetIfNotCompleted() {
        guard [.pending, .downloading].contains(status) else { return }
        status = .paused
    }

    mutating func complete() {
        status = .completed
        percent = 1
        speed = ""
        error = nil
    }
}
