// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kbglow",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/totota-08/kbdlight.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "kbglow",
            dependencies: [
                .product(name: "MacKeyboardBacklight", package: "kbdlight")
            ],
            path: "Sources/kbglow"
        )
    ]
)
