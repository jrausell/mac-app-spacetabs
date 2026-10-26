// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceTabs",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "SpaceTabs", targets: ["SpaceTabs"])],
    targets: [
        .target(name: "SpaceTabsCore", resources: [.process("Localization/Resources")]),
        .executableTarget(name: "SpaceTabs", dependencies: ["SpaceTabsCore"]),
        .testTarget(name: "SpaceTabsCoreTests", dependencies: ["SpaceTabsCore"]),
        .testTarget(name: "SpaceTabsTests", dependencies: ["SpaceTabs"]),
    ]
)
