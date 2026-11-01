// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SopranoDesktop",
    platforms: [.macOS(.v14)],
    targets: [
        // Theme engine: palettes, pair resolution, settings, snapshot, config-file edits and
        // every theme-file generator. Foundation only, no AppKit.
        .target(
            name: "SopranoDesktopCore",
            path: "Sources/SopranoDesktopCore"
        ),
        .executableTarget(
            name: "SopranoDesktop",
            dependencies: ["SopranoDesktopCore"],
            path: "Sources/SopranoDesktop",
            // AppIcon.icns is packaged by scripts/package-app.sh, not as an SPM resource.
            exclude: ["Vendored/SOPRANO_COMMIT", "Resources/AppIcon.icns"],
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "SopranoDesktopTests",
            dependencies: ["SopranoDesktop", "SopranoDesktopCore"],
            path: "Tests/SopranoDesktopTests",
            swiftSettings: [
                .unsafeFlags(["-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
                .linkedFramework("Testing"),
            ]
        ),
    ]
)
