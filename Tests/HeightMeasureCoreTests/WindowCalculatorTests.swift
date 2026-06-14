import XCTest
import simd
@testable import HeightMeasureCore

/// 窓枠サイズ計測（§4.3 / §11）の検証。ARKit/RealityKit 非依存で `swift test` 実行できる。
final class WindowCalculatorTests: XCTestCase {

    private let tolerance = 0.01

    // 平面上の 1.2m × 1.5m の長方形 → 幅1.20 / 高さ1.50 / 対角√(1.2²+1.5²)=1.921
    func test_rectangle_1_2x1_5() {
        let size = WindowCalculator.size(
            topLeft: SIMD3<Double>(0, 1.5, 0),
            topRight: SIMD3<Double>(1.2, 1.5, 0),
            bottomRight: SIMD3<Double>(1.2, 0, 0),
            bottomLeft: SIMD3<Double>(0, 0, 0)
        )
        XCTAssertNotNil(size)
        XCTAssertEqual(size!.width, 1.20, accuracy: tolerance)
        XCTAssertEqual(size!.height, 1.50, accuracy: tolerance)
        XCTAssertEqual(size!.diagonal, (1.2 * 1.2 + 1.5 * 1.5).squareRoot(), accuracy: tolerance)
    }

    // 垂直面（z=2）上の 0.8m 正方形 → 幅0.80 / 高さ0.80 / 対角√(0.8²+0.8²)=1.131
    func test_square_0_8_onVerticalPlane() {
        let size = WindowCalculator.size(
            topLeft: SIMD3<Double>(0, 0.8, 2),
            topRight: SIMD3<Double>(0.8, 0.8, 2),
            bottomRight: SIMD3<Double>(0.8, 0, 2),
            bottomLeft: SIMD3<Double>(0, 0, 2)
        )
        XCTAssertNotNil(size)
        XCTAssertEqual(size!.width, 0.80, accuracy: tolerance)
        XCTAssertEqual(size!.height, 0.80, accuracy: tolerance)
        XCTAssertEqual(size!.diagonal, (0.8 * 0.8 + 0.8 * 0.8).squareRoot(), accuracy: tolerance)
    }

    // 退化（四隅が同一点）→ nil
    func test_degenerate_returnsNil() {
        let p = SIMD3<Double>(1, 1, 1)
        XCTAssertNil(WindowCalculator.size(topLeft: p, topRight: p, bottomRight: p, bottomLeft: p))
    }

    // 奥行き（壁の法線方向）のノイズは平面投影で除去され、寸法に影響しない。
    // 1.2×1.5 の四隅の Z を数cm ばらつかせても 幅1.20 / 高さ1.50。
    func test_depthNoise_ignored_withPlaneNormal() {
        let size = WindowCalculator.size(
            topLeft: SIMD3<Double>(0, 1.5, 0.05),
            topRight: SIMD3<Double>(1.2, 1.5, -0.03),
            bottomRight: SIMD3<Double>(1.2, 0, 0.04),
            bottomLeft: SIMD3<Double>(0, 0, -0.02),
            planeNormal: SIMD3<Double>(0, 0, 1)
        )
        XCTAssertNotNil(size)
        XCTAssertEqual(size!.width, 1.20, accuracy: tolerance)
        XCTAssertEqual(size!.height, 1.50, accuracy: tolerance)
    }

    // 傾いた壁面（法線が斜め）でも、平面へ投影して正しい 1.0×0.8 を得る。
    func test_tiltedPlane_1_0x0_8() {
        let s = 0.35355339   // 0.5 / √2
        let size = WindowCalculator.size(
            topLeft: SIMD3<Double>(s, 1.4, -s),
            topRight: SIMD3<Double>(-s, 1.4, s),
            bottomRight: SIMD3<Double>(-s, 0.6, s),
            bottomLeft: SIMD3<Double>(s, 0.6, -s),
            planeNormal: SIMD3<Double>(1, 0, 1)
        )
        XCTAssertNotNil(size)
        XCTAssertEqual(size!.width, 1.0, accuracy: tolerance)
        XCTAssertEqual(size!.height, 0.8, accuracy: tolerance)
    }
}
