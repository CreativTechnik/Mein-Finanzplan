// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MeinFinanzplan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeinFinanzplan", targets: ["MeinFinanzplan"]),
        .executable(name: "VerifyFinanceCore", targets: ["VerifyFinanceCore"])
    ],
    targets: [
        .target(name: "FinanceCore"),
        .executableTarget(
            name: "MeinFinanzplan",
            dependencies: ["FinanceCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "VerifyFinanceCore",
            dependencies: ["FinanceCore"]
        )
    ]
)
