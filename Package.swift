// swift-tools-version: 6.1

import PackageDescription

let package = Package(
	name: "hdr-resize",
	platforms: [
		.macOS(.v13)
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.1"),
	],
	targets: [
		.executableTarget(
			name: "hdr-resize",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			]
		),
	]
)
