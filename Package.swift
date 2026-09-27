// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Weave",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.executable(name: "Weave", targets: ["Weave"])],
    targets: [
        .executableTarget(
            name: "Weave",
            resources: [.copy("Resources/CodeFormatting"), .process("Resources/en.lproj"), .process("Resources/zh-Hans.lproj")]),
        .testTarget(name: "WeaveTests", dependencies: ["Weave"]),
    ]
)
