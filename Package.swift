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
        .executable(name: "esys", targets: ["EsysCLI"])
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
        .testTarget(
            name: "EsysCoreTests",
            dependencies: ["EsysCore"],
            path: "Tests/EsysCoreTests"
        )
    ]
)
