// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kbglow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "kbglow",
            path: "Sources/kbglow",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist so macOS can show the system-audio-recording
                // permission prompt (TCC) for this bare CLI binary.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/kbglow/Info.plist",
                ])
            ]
        )
    ]
)
