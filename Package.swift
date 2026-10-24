// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LLMTrack",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LLMTrack", targets: ["LLMTrack"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LLMTrack",
            dependencies: [],
            path: "Sources/LLMTrack"
        )
    ]
)
