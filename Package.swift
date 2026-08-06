// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kbglow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "kbglow",
            path: "Sources/kbglow"
        )
    ]
)
