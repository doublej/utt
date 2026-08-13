// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "asrspike",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.15.5")
    ],
    targets: [
        .executableTarget(
            name: "asrspike",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ]
)
