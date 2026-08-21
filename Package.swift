// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Imageview",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "ImageviewCore", targets: ["ImageviewCore"]),
        .executable(name: "Imageview", targets: ["ImageviewApp"]),
    ],
    targets: [
        .target(name: "ImageviewCore"),
        .executableTarget(
            name: "ImageviewApp",
            dependencies: ["ImageviewCore"]
        ),
        .testTarget(
            name: "ImageviewCoreTests",
            dependencies: ["ImageviewCore"]
        ),
    ]
)
