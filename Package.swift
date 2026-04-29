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
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
    ],
    targets: [
        .target(
            name: "ShortyCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
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
