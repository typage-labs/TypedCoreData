// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TypedCoreData",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "TypedCoreData",
            targets: ["TypedCoreData"]
        ),
    ],
    targets: [
        .target(name: "TypedCoreData"),
        // Test-only Objective-C boundary for observing native validation exceptions.
        .target(
            name: "CoreDataExceptionSupport",
            path: "Tests/CoreDataExceptionSupport",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "TypedCoreDataTests",
            dependencies: ["TypedCoreData", "CoreDataExceptionSupport"]
        ),
    ],
    // Swift 6 language mode enables complete strict concurrency checking.
    swiftLanguageModes: [.v6]
)
