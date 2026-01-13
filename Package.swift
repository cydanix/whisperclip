// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WhisperClip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "WhisperClip",
            targets: ["WhisperClip"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.21.2"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperClip",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "WhisperClipTests",
            dependencies: ["WhisperClip"],
            path: "Tests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
