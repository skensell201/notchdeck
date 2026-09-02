// swift-tools-version: 6.0
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
        .target(name: "NotchWindow", dependencies: ["NotchCore"]),
        .target(name: "NotchUI", dependencies: ["NotchWindow"]),
        .executableTarget(name: "NotchDeckApp", dependencies: ["NotchUI"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"])
    ]
)
