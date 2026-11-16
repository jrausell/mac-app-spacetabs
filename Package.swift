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
        .executableTarget(
            name: "SpaceTabsFinder", dependencies: ["SpaceTabsCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        .executableTarget(name: "DesktopProbe", dependencies: ["SpaceTabsCore"], path: "Tools/DesktopProbe"),
        .testTarget(name: "SpaceTabsCoreTests", dependencies: ["SpaceTabsCore"]),
        .testTarget(name: "SpaceTabsTests", dependencies: ["SpaceTabs"]),
    ]
)
