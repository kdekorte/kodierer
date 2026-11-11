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
        .executable(name: "kodierer", targets: ["KodiererCLI"]),
        .executable(name: "KodiererApp", targets: ["KodiererApp"])
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
            name: "KodiererApp",
            dependencies: ["KodiererCore"],
            path: "Sources/KodiererApp"
        ),
        .testTarget(
            name: "KodiererCoreTests",
            dependencies: ["KodiererCore"],
            path: "Tests/KodiererCoreTests"
        )
    ]
)
