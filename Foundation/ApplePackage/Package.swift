// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ApplePackage",
    products: [
        .library(name: "ApplePackage", targets: ["ApplePackage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
    ],
    targets: [
        .target(name: "ApplePackage", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "ApplePackageTests", dependencies: ["ApplePackage"]),
    ]
)
