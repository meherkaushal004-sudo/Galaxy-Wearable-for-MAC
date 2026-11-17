// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BudsBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BudsBar",
            path: "Sources/BudsBar",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
    ]
)
