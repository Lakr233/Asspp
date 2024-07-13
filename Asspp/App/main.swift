//
//  main.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = availableDirectories[0]
    .appendingPathComponent("Asspp")
do {
    let enumerator = FileManager.default.enumerator(atPath: documentsDirectory.path)
    while let file = enumerator?.nextObject() as? String {
        let path = documentsDirectory.appendingPathComponent(file)
        if let content = try? FileManager.default.contentsOfDirectory(atPath: path.path),
           content.isEmpty
        { try? FileManager.default.removeItem(at: path) }
    }
}

try? FileManager.default.createDirectory(
    at: documentsDirectory,
    withIntermediateDirectories: true,
    attributes: nil
)
let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(bundleIdentifier)
do {
    let enumerator = FileManager.default.enumerator(atPath: temporaryDirectory.path)
    while let file = enumerator?.nextObject() as? String {
        let path = temporaryDirectory.appendingPathComponent(file)
        if let content = try? FileManager.default.contentsOfDirectory(atPath: path.path),
           content.isEmpty
        { try? FileManager.default.removeItem(at: path) }
    }
}

try? FileManager.default.createDirectory(
    at: temporaryDirectory,
    withIntermediateDirectories: true,
    attributes: nil
)

_ = ProcessInfo.processInfo.hostName

AppStore.this.setupGUID()
_ = Downloads.this

App.main()

private struct App: SwiftUI.App {
    var body: some Scene {
        WindowGroup { MainView() }
    }
}
