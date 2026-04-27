// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shorty",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ShortyCore",
            targets: ["ShortyCore"]
        ),
        .executable(
            name: "Shorty",
            targets: ["Shorty"]
        ),
    ],
    targets: [
        .target(
            name: "ShortyCore"
        ),
        .executableTarget(
            name: "Shorty",
            dependencies: ["ShortyCore"]
        ),
        .testTarget(
            name: "ShortyCoreTests",
            dependencies: ["ShortyCore"]
        ),
    ]
)
