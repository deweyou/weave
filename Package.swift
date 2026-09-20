// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Weave",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.executable(name: "Weave", targets: ["Weave"])],
    targets: [
        .executableTarget(name: "Weave"),
        .testTarget(name: "WeaveTests", dependencies: ["Weave"]),
    ]
)
