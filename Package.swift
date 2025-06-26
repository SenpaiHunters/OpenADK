// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "OpenADK",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OpenADK",
            targets: ["OpenADK"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "OpenADKObjC",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/OpenADKObjC",
            publicHeadersPath: "."
        ),
        .target(
            name: "OpenADK",
            dependencies: [
                "OpenADKObjC",
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/OpenADK"
        ),
        .testTarget(
            name: "OpenADKTests",
            dependencies: ["OpenADK"]
        )
    ]
)
