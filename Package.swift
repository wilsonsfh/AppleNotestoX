// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleNotestoX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AppleNotestoX", targets: ["AppleNotestoX"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2")
    ],
    targets: [
        .executableTarget(
            name: "AppleNotestoX",
            dependencies: ["SwiftSoup", "KeychainAccess"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AppleNotestoXTests",
            dependencies: ["AppleNotestoX"]
        )
    ]
)
