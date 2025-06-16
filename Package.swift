// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "OpenADK",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "OpenADK",
            targets: ["OpenADK"]
        ),
    ],
    targets: [
        .target(
            name: "OpenADKObjC",
            path: "Sources/OpenADKObjC",
            publicHeadersPath: "." // Exposes OpenADKObjC.h + WKWebsiteDataStore+Private.h
        ),
        .target(
            name: "OpenADK",
            dependencies: ["OpenADKObjC"],
            path: "Sources/OpenADK"
        ),
        .testTarget(
            name: "OpenADKTests",
            dependencies: ["OpenADK"]
        )
    ]
)
