// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexHistorySync",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexHistorySync", targets: ["CodexHistorySync"])],
    targets: [
        .executableTarget(
            name: "CodexHistorySync",
            path: "macos",
            exclude: ["CodexHistorySync.entitlements", "Info.plist"],
            resources: [.process("Resources")]
        )
    ]
)
