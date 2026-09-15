// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QE",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "QE", targets: ["QE"])],
    targets: [
        .target(name: "QECore"),
        .executableTarget(name: "QE", dependencies: ["QECore"]),
        .executableTarget(name: "QEChecks", dependencies: ["QECore"], path: "Tests/QECoreTests")
    ]
)
