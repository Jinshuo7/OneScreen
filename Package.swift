// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OneScreen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OneScreen", targets: ["OneScreen"])
    ],
    targets: [
        .executableTarget(
            name: "OneScreen",
            path: "Sources/OneScreen"
        )
    ]
)
