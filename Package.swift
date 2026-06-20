// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "escctrl",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "escctrl",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/escctrl",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "escctrlTests",
            dependencies: ["escctrl"],
            path: "Tests/escctrlTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
