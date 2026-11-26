// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Poltergeist",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Poltergeist", targets: ["Poltergeist"]),
        .library(name: "PoltergeistKit", targets: ["PoltergeistKit"])
    ],
    targets: [
        .target(name: "PoltergeistKit", path: "Sources/PoltergeistKit"),
        .executableTarget(
            name: "Poltergeist",
            dependencies: ["PoltergeistKit"],
            path: "Sources/Poltergeist"
        ),
        .testTarget(
            name: "PoltergeistKitTests",
            dependencies: ["PoltergeistKit"],
            path: "Tests/PoltergeistKitTests"
        )
    ]
)
