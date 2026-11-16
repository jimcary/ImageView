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
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.6.0"),
    ],
    targets: [
        .target(name: "ImageviewCore", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]),
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
