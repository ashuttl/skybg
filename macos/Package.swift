// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Skybg",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything but the window: the sun, the styles, the renderer, the
        // wallpaper and the timer. A port of bin/skybg.
        .target(name: "SkyKit"),
        .executableTarget(name: "Skybg", dependencies: ["SkyKit"]),
        .testTarget(name: "SkyKitTests", dependencies: ["SkyKit"], exclude: ["parity.json"]),
    ]
)
