// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RaicodePet",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RaicodePetCore"),
        .executableTarget(name: "RaicodePet", dependencies: ["RaicodePetCore"]),
        .testTarget(name: "RaicodePetCoreTests", dependencies: ["RaicodePetCore"]),
    ]
)
