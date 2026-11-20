// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZoneWatchKit",
    platforms: [
        .iOS(.v17),
        // macOS only so `swift test` runs fast on a Mac and in CI.
        .macOS(.v14),
    ],
    products: [
        .library(name: "ZoneWatchKit", targets: ["ZoneWatchKit"]),
    ],
    targets: [
        .target(name: "ZoneWatchKit"),
        .testTarget(name: "ZoneWatchKitTests", dependencies: ["ZoneWatchKit"]),
    ]
)
