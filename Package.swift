// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "Shared"),
        .executableTarget(name: "perch-hook", dependencies: ["Shared"]),
        .executableTarget(name: "spike-server", dependencies: ["Shared"]), // throwaway
        .executableTarget(name: "Perch", dependencies: ["Shared"]),
        .testTarget(name: "PerchTests", dependencies: ["Shared", "Perch", "perch-hook"]),
    ],
    swiftLanguageModes: [.v5]
)
