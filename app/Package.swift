// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mira",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mira", targets: ["MiraApp"]),
        .executable(name: "mira-bench", targets: ["MiraBench"])
    ],
    targets: [
        .target(
            name: "MiraCore",
            path: "Sources/MiraCore"
        ),
        .executableTarget(
            name: "MiraApp",
            dependencies: ["MiraCore"],
            path: "Sources/MiraApp"
        ),
        .executableTarget(
            name: "MiraBench",
            dependencies: ["MiraCore"],
            path: "Sources/MiraBench"
        )
    ]
)
