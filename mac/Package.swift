// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BfmeFoundationProject",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Portable library products (compile on Linux and macOS)
        .library(name: "BfmeHttpInstruments", targets: ["BfmeHttpInstruments"]),
        .library(name: "BfmeKitCore", targets: ["BfmeKitCore"]),
        .library(name: "BfmeDirectXRuntime", targets: ["BfmeDirectXRuntime"]),
        // Additional products reserved for later features. They currently expose the
        // same portable core surface; macOS-specific UI targets are added in later
        // features and gated with `.when(platforms: [.macOS])` inside those targets.
        .library(name: "BfmeKit", targets: ["BfmeKit"]),
        .library(name: "BfmeWorkshopKit", targets: ["BfmeWorkshopKit"]),
        .library(name: "BfmeOnlineKit", targets: ["BfmeOnlineKit"]),
        .library(name: "BfmeOnlineKitUI", targets: ["BfmeOnlineKitUI"]),
        .executable(name: "BfmeLauncherApp", targets: ["BfmeLauncherApp"])
    ],
    targets: [
        // System module wrapping zlib (available on Linux and macOS).
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib",
            pkgConfig: "zlib",
            providers: [
                .apt(["zlib1g-dev"]),
                .yum(["zlib-devel"]),
                .brew(["zlib"])
            ]
        ),

        .target(
            name: "BfmeHttpInstruments",
            dependencies: ["CZlib"],
            path: "Sources/BfmeHttpInstruments"
        ),

        .target(
            name: "BfmeKitCore",
            dependencies: [],
            path: "Sources/BfmeKitCore"
        ),

        .target(
            name: "BfmeDirectXRuntime",
            dependencies: ["BfmeKitCore"],
            path: "Sources/BfmeDirectXRuntime",
            resources: [
                .copy("Resources/dx9_redist.zip")
            ]
        ),

        // Stub targets for later features. Each depends on the portable core so it
        // can expose a real module even before its feature lands.
        .target(
            name: "BfmeKit",
            dependencies: ["BfmeKitCore", "BfmeHttpInstruments"],
            path: "Sources/BfmeKit",
            resources: [
                .copy("Resources")
            ]
        ),
        .target(
            name: "BfmeWorkshopKit",
            dependencies: ["BfmeKitCore", "BfmeHttpInstruments"],
            path: "Sources/BfmeWorkshopKit"
        ),
        .target(
            name: "BfmeOnlineKit",
            dependencies: ["BfmeKitCore", "BfmeHttpInstruments"],
            path: "Sources/BfmeOnlineKit"
        ),
        .target(
            name: "BfmeOnlineKitUI",
            dependencies: ["BfmeOnlineKit"],
            path: "Sources/BfmeOnlineKitUI"
        ),
        .executableTarget(
            name: "BfmeLauncherApp",
            dependencies: [
                "BfmeKit",
                "BfmeKitCore",
                "BfmeHttpInstruments",
                "BfmeDirectXRuntime",
                "BfmeWorkshopKit",
                "BfmeOnlineKit"
            ],
            path: "Sources/BfmeLauncherApp"
        ),

        // Tests
        .testTarget(
            name: "BfmeHttpInstrumentsTests",
            dependencies: ["BfmeHttpInstruments", "CZlib"],
            path: "Tests/BfmeHttpInstrumentsTests"
        ),
        .testTarget(
            name: "BfmeKitCoreTests",
            dependencies: ["BfmeKitCore"],
            path: "Tests/BfmeKitCoreTests"
        ),
        .testTarget(
            name: "BfmeDirectXRuntimeTests",
            dependencies: ["BfmeDirectXRuntime"],
            path: "Tests/BfmeDirectXRuntimeTests"
        ),
        .testTarget(
            name: "BfmeKitTests",
            dependencies: ["BfmeKit", "BfmeKitCore"],
            path: "Tests/BfmeKitTests"
        ),
        .testTarget(
            name: "BfmeWorkshopKitTests",
            dependencies: ["BfmeWorkshopKit", "BfmeKit", "BfmeKitCore", "BfmeHttpInstruments"],
            path: "Tests/BfmeWorkshopKitTests"
        ),
        .testTarget(
            name: "BfmeOnlineKitTests",
            dependencies: ["BfmeOnlineKit", "BfmeKit", "BfmeKitCore", "BfmeHttpInstruments"],
            path: "Tests/BfmeOnlineKitTests"
        )
    ]
)
