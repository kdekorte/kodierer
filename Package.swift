// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "esys",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "EsysCore", targets: ["EsysCore"]),
        .executable(name: "esys", targets: ["EsysCLI"]),
        .executable(name: "EsysApp", targets: ["EsysApp"])
    ],
    targets: [
        .target(
            name: "EsysCore",
            path: "Sources/EsysCore"
        ),
        .executableTarget(
            name: "EsysCLI",
            dependencies: ["EsysCore"],
            path: "Sources/EsysCLI"
        ),
        .executableTarget(
            name: "EsysApp",
            dependencies: ["EsysCore"],
            path: "Sources/EsysApp"
        ),
        .testTarget(
            name: "EsysCoreTests",
            dependencies: ["EsysCore"],
            path: "Tests/EsysCoreTests"
        )
    ]
)
