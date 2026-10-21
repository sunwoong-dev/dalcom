// swift-tools-version: 6.0
import PackageDescription

// 앱과 위젯이 함께 쓰는 순수 로직 패키지. 외부 의존성은 두지 않는다.
let package = Package(
    name: "DateCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DateCore", targets: ["DateCore"]),
    ],
    targets: [
        .target(name: "DateCore"),
        .testTarget(name: "DateCoreTests", dependencies: ["DateCore"]),
    ]
)
