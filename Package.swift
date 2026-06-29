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
            resources: [.process("Resources")],
            linkerSettings: [
                // Embed an Info.plist into the executable so the Speech framework can read
                // NSSpeechRecognitionUsageDescription (it traps at runtime if missing).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "AppleNotestoX-Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "AppleNotestoXTests",
            dependencies: ["AppleNotestoX"]
        )
    ]
)
