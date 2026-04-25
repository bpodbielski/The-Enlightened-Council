// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForceGraphSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ForceGraphBench",
            path: "Sources/ForceGraphBench",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
