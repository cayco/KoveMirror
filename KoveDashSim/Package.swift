// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoveDashSim",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KoveDashSim", targets: ["KoveDashSim"])
    ],
    targets: [
        .executableTarget(
            name: "KoveDashSim",
            path: "Sources"
        )
    ]
)
