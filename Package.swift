// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RaicodePet",
    // The SDK version recorded in the binary follows this. Below 26, macOS runs the app in
    // pre–Liquid Glass compatibility mode and every glass API falls back to an old blur.
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "RaicodePetCore"),
        .executableTarget(name: "RaicodePet", dependencies: ["RaicodePetCore"]),
        .testTarget(name: "RaicodePetCoreTests", dependencies: ["RaicodePetCore"]),
    ]
)
