// swift-tools-version:5.9
// UsageMonitor — dependency-free Swift Package.
// Core logic (parser/transport/service) is a library so it can be unit tested
// without launching the GUI, and executables are produced for the .app bundle
// and the QA smoke diagnostic.
import PackageDescription

let package = Package(
    name: "UsageMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "UsageMonitorCore",
            path: "Sources/UsageMonitorCore"
        ),
        .executableTarget(
            name: "UsageMonitorApp",
            dependencies: ["UsageMonitorCore"],
            path: "Sources/UsageMonitorApp"
        ),
        .executableTarget(
            name: "UsageMonitorCLI",
            dependencies: ["UsageMonitorCore"],
            path: "Sources/UsageMonitorCLI"
        ),
        .testTarget(
            name: "UsageMonitorCoreTests",
            dependencies: ["UsageMonitorCore"],
            path: "Tests/UsageMonitorCoreTests"
        ),
        // Application wiring tests: the composition root, the status item lifecycle and
        // the save-then-probe credential flows, against the real app module.
        .testTarget(
            name: "UsageMonitorAppTests",
            dependencies: ["UsageMonitorApp"],
            path: "Tests/UsageMonitorAppTests"
        )
    ]
)
