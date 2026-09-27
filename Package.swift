// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mizan",
    platforms: [.macOS(.v14)],
    targets: [
        // المنطق: قاعدة البيانات، المستورد، الحسابات — بلا واجهة، قابل للاختبار
        .target(name: "MizanCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        // التطبيق: شريط القوائم والواجهة
        .executableTarget(name: "Mizan", dependencies: ["MizanCore"]),
        .testTarget(name: "MizanCoreTests", dependencies: ["MizanCore"]),
    ]
)
