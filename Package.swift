// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "kodierer",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "KodiererCore", targets: ["KodiererCore"]),
        .executable(name: "kodierer-cli", targets: ["KodiererCLI"]),
        .executable(name: "Kodierer", targets: ["Kodierer"])
    ],
    targets: [
        .target(
            name: "KodiererCore",
            path: "Sources/KodiererCore"
        ),
        .executableTarget(
            name: "KodiererCLI",
            dependencies: ["KodiererCore"],
            path: "Sources/KodiererCLI"
        ),
        .executableTarget(
            name: "Kodierer",
            dependencies: ["KodiererCore"],
            path: "Sources/Kodierer"
        ),
        .testTarget(
            name: "KodiererCoreTests",
            dependencies: ["KodiererCore"],
            path: "Tests/KodiererCoreTests"
        )
    ]
)
