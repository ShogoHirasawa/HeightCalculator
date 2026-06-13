// swift-tools-version: 5.9
import PackageDescription

// HeightCalculator（§5.3 の純関数）を macOS ネイティブで `swift test` できるようにするための
// テスト専用パッケージ。本番コードは Xcode プロジェクト（HeightMeasure.xcodeproj）が正であり、
// ここではソースを複製せず HeightMeasure/HeightCalculator.swift を直接参照する。
//
// 背景: 当環境の Xcode 16.4 には iOS 18.5 シミュレータランタイムが無く（17.5 のみ）、
// `xcodebuild test` の宛先解決が通らないため、シミュレータ非依存の純ロジックは SPM で検証する。
let package = Package(
    name: "HeightMeasureCore",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "HeightMeasureCore",
            path: "HeightMeasure",
            exclude: [
                "HeightMeasureApp.swift",
                "ContentView.swift",
                "ARViewContainer.swift",
                "MeasureViewModel.swift",
                "OverlayView.swift",
                "MeasureState.swift",
                "MeasureMode.swift",
                "Measurement.swift",
                "Assets.xcassets",
                "Info.plist",
            ],
            sources: ["HeightCalculator.swift", "WindowCalculator.swift", "WindowSize.swift"]
        ),
        .testTarget(
            name: "HeightMeasureCoreTests",
            dependencies: ["HeightMeasureCore"],
            path: "Tests/HeightMeasureCoreTests"
        ),
    ]
)
