// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ChaiAIStory", platforms: [.iOS(.v17), .macOS(.v13)], products: [.library(name: "StoryCore", targets: ["StoryCore"])], targets: [.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"), .target(name: "StoryCore", dependencies: ["CSQLite"]), .testTarget(name: "StoryCoreTests", dependencies: ["StoryCore"])])
