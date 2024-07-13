//
//  Digger.swift
//  Digger
//
//  Created by ant on 2017/10/25.
//  Copyright © 2017年 github.cornerant. All rights reserved.
//

import Foundation

public let digger = "Digger"

/// start download with url

@discardableResult
public func download(_ url: DiggerURL) -> DiggerSeed {
    DiggerManager.shared.download(with: url)
}
