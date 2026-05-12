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
        .library(name: "BfmeKit", targets: ["BfmeKit"]),
        .library(name: "BfmeWorkshopKit", targets: ["BfmeWorkshopKit"]),
        .library(name: "BfmeOnlineKit", targets: ["BfmeOnlineKit"]),
        // UI library: the whole body is gated with `#if canImport(SwiftUI)` so
        // Linux compiles an empty module and macOS gets the full SwiftUI
        // surface.
        .library(name: "BfmeOnlineKitUI", targets: ["BfmeOnlineKitUI"]),
        // Executable: on macOS this is the SwiftUI launcher app; on Linux the
        // `@main` stub prints module versions so `swift build` still produces
        // a working binary.
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
            dependencies: ["BfmeKitCore", "BfmeHttpInstruments", "BfmeKit"],
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
            path: "Sources/BfmeOnlineKitUI",
            resources: [
                .copy("Fonts")
            ]
        ),
        .executableTarget(
            name: "BfmeLauncherApp",
            dependencies: [
                "BfmeKit",
                "BfmeKitCore",
                "BfmeHttpInstruments",
                "BfmeDirectXRuntime",
                "BfmeWorkshopKit",
                "BfmeOnlineKit",
                "BfmeOnlineKitUI"
            ],
            path: "Sources/BfmeLauncherApp",
            resources: [
                .copy("Resources")
            ]
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
        ),
        // Launcher-app tests exercise the portable Core logic (AppState,
        // BfmeLaunchManager, SystemDisplayManager). They run on macOS only;
        // on Linux the test target is excluded so the SwiftUI `@main` body
        // never needs to build.
        .testTarget(
            name: "BfmeLauncherAppTests",
            dependencies: ["BfmeLauncherApp", "BfmeKit", "BfmeKitCore"],
            path: "Tests/BfmeLauncherAppTests"
        )
    ]
)
