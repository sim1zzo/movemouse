// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoveMouseMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MoveMouseMac", targets: ["MoveMouseMac"])
    ],
    targets: [.executableTarget(name: "MoveMouseMac")]
)
