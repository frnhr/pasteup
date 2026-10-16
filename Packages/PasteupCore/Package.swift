// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "PasteupCore",
	platforms: [
		.macOS(.v14)
	],
	products: [
		.library(name: "PasteupCore", targets: ["PasteupCore"])
	],
	targets: [
		.target(name: "PasteupCore"),
		.testTarget(name: "PasteupCoreTests", dependencies: ["PasteupCore"])
	]
)
