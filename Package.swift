// swift-tools-version: 6.3
//
//  Package.swift
//  WebKitDOM
//
//  Created by Neon.
//

import PackageDescription

let package = Package(
    name: "WebKitDOM",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "WebKitDOM", targets: ["WebKitDOM"])
    ],
    targets: [
        .target(
            name: "WebKitDOM",
            path: "WebKitDOM/Sources/WebKitDOM"
        ),
        .testTarget(
            name: "WebKitDOMTests",
            dependencies: ["WebKitDOM"],
            path: "WebKitDOM/Tests/WebKitDOMTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
