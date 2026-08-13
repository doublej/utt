// swift-tools-version: 6.3
import PackageDescription

// Pure logic only. No AppKit, no TCC, no audio hardware — so `swift test` runs in a
// second without an app bundle or a single permission prompt. Anything that needs a
// framework belongs in Utt/Clients/ instead.
let package = Package(
    name: "UttCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "UttCore", targets: ["UttCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.14.1")
    ],
    targets: [
        .target(
            name: "UttCore",
            dependencies: [.product(name: "Dependencies", package: "swift-dependencies")]
        ),
        .testTarget(
            name: "UttCoreTests",
            dependencies: [
                "UttCore",
                .product(name: "Dependencies", package: "swift-dependencies")
            ]
        )
    ]
)
