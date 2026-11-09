// swift-tools-version: 5.9
// HUDCore（純粋ロジック）を Linux / macOS / Windows でテストするためのパッケージ。
// ソースは HUDNavigator.swiftpm/Core にあり、Swift Playgrounds 版・正式アプリ版と共有している。
import PackageDescription

let package = Package(
    name: "HUDCore",
    platforms: [.iOS("18.0"), .macOS("14.0")],
    products: [
        .library(name: "HUDCore", targets: ["HUDCore"]),
    ],
    targets: [
        .target(
            name: "HUDCore",
            path: "HUDNavigator.swiftpm/Core"
        ),
        .testTarget(
            name: "HUDCoreTests",
            dependencies: ["HUDCore"],
            path: "Tests/HUDCoreTests"
        ),
    ]
)
