// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RightLayout",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RightLayout", targets: ["RightLayout"]),
        .executable(name: "RightLayoutApp", targets: ["RightLayoutApp"]),
        .executable(name: "RightLayoutTestHost", targets: ["RightLayoutTestHost"]),
        .executable(name: "Benchmark", targets: ["Benchmark"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RightLayout",
            dependencies: [],
            path: "RightLayout/Sources",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "RightLayoutApp",
            dependencies: ["RightLayout"],
            path: "RightLayout/AppEntry", // We'll move RightLayoutApp.swift here
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "RightLayoutTestHost",
            dependencies: ["RightLayout"],
            path: "Tools/RightLayoutTestHost",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "Benchmark",
            dependencies: ["RightLayout"],
            path: "Tools/Benchmark"
        ),
        .testTarget(
            name: "RightLayoutTests",
            dependencies: ["RightLayout"],
            path: "RightLayout/Tests"
        )
    ]
)
