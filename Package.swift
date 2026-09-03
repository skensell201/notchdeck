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
        .target(name: "Clipboard", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .target(name: "Shelf", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .target(name: "Pomodoro", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .target(name: "Stats", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .target(name: "Mirror", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .target(name: "SystemHUD", dependencies: ["Support"]),
        .executableTarget(name: "NotchDeckApp", dependencies: ["NotchCore", "NotchUI", "NotchWindow", "Support", "Media", "Shelf", "Clipboard", "Pomodoro", "Stats", "Mirror", "Shortcuts", "Agenda", "SystemHUD"]),
        .target(name: "Shortcuts", dependencies: ["NotchCore", "NotchUI", "Support"]),
        // Named for what it shows rather than for EventKit: a target called
        // `Calendar` shadows `Foundation.Calendar` in every file that imports it,
        // and this module is nothing but date arithmetic.
        .target(name: "Agenda", dependencies: ["NotchCore", "NotchUI", "Support"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
        .testTarget(name: "MediaTests", dependencies: ["Media"]),
        .testTarget(name: "ClipboardTests", dependencies: ["Clipboard"]),
        .testTarget(name: "ShelfTests", dependencies: ["Shelf"]),
        .testTarget(name: "PomodoroTests", dependencies: ["Pomodoro"]),
        .testTarget(name: "StatsTests", dependencies: ["Stats"]),
        .testTarget(name: "SystemHUDTests", dependencies: ["SystemHUD"]),
        .testTarget(name: "ShortcutsTests", dependencies: ["Shortcuts"]),
        .testTarget(name: "AgendaTests", dependencies: ["Agenda", "NotchUI"])
    ]
)
