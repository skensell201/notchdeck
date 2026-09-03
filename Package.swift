// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "notchdeck",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "notchdeck", targets: ["NotchDeckApp"])
    ],
    targets: [
        .target(name: "Support"),
        .target(name: "NotchCore", dependencies: ["Support"]),
        .target(name: "NotchUI", dependencies: ["NotchCore"]),
        .target(name: "NotchWindow", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .target(name: "Media", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .executableTarget(name: "NotchDeckApp", dependencies: ["NotchCore", "NotchUI", "NotchWindow", "Support", "Media"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
        .testTarget(name: "MediaTests", dependencies: ["Media"])
    ]
)
