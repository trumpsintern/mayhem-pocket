// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ARAMMayhem", platforms: [.macOS(.v13)], products: [.executable(name: "ARAMMayhem", targets: ["ARAMMayhem"])], targets: [.executableTarget(name: "ARAMMayhem")])
