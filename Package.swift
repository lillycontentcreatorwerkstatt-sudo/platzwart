// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Platzwart",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Platzwart", targets: ["Platzwart"])],
    targets: [
        .executableTarget(name: "Platzwart")
    ]
)
