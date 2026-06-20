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

    // MARK: - 軸拘束（方式A: 重力基準）

    // 垂直壁（法線 +z）の重力ベース軸: v=鉛直(0,1,0)、u=平面内水平で v・法線に直交。
    func test_planeAxes_verticalWall() {
        let axes = WindowCalculator.planeAxes(normal: SIMD3<Double>(0, 0, 1))
        XCTAssertNotNil(axes)
        let (u, v) = axes!
        XCTAssertEqual(simd_length(u), 1.0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(v), 1.0, accuracy: 1e-6)
        XCTAssertEqual(v.y, 1.0, accuracy: 1e-6)              // 鉛直は重力方向
        XCTAssertEqual(simd_dot(u, v), 0.0, accuracy: 1e-6)   // 直交
        XCTAssertEqual(u.z, 0.0, accuracy: 1e-6)              // 平面内（法線方向の成分なし）
    }

    // 壁がほぼ水平（法線が上向き）だと鉛直が決められず nil。
    func test_planeAxes_horizontalWall_returnsNil() {
        XCTAssertNil(WindowCalculator.planeAxes(normal: SIMD3<Double>(0, 1, 0)))
    }

    // 直線への射影: axis 方向は point を採用し、それ以外の成分は origin に一致する。
    func test_projectOntoLine() {
        let p = WindowCalculator.projectOntoLine(
            SIMD3<Double>(2, 3, 5),
            origin: SIMD3<Double>(1, 1, 1),
            axis: SIMD3<Double>(1, 0, 0))
        XCTAssertEqual(p.x, 2.0, accuracy: 1e-6)
        XCTAssertEqual(p.y, 1.0, accuracy: 1e-6)
        XCTAssertEqual(p.z, 1.0, accuracy: 1e-6)
    }

    // 方式A の拘束パイプライン: 右上/右下の生交点に狙いズレ（高さ・奥行き）があっても、
    // 左上を基準に水平/鉛直へ拘束すると窓枠に沿う長方形になる。幅1.0 / 高さ1.6。
    func test_constraint_snapsToRectangle_despiteAimError() {
        let normal = SIMD3<Double>(0, 0, 1)
        let axes = WindowCalculator.planeAxes(normal: normal)!
        let tl = SIMD3<Double>(0, 2, 0)
        let rawTR = SIMD3<Double>(1.0, 2.07, -0.1)   // 7cm 高い・10cm 手前にズレた狙い
        let rawBR = SIMD3<Double>(1.08, 0.4, 0.12)   // 8cm 右・12cm 奥にズレた狙い

        let tr = WindowCalculator.projectOntoLine(rawTR, origin: tl, axis: axes.u)  // 左上と同じ高さ
        let br = WindowCalculator.projectOntoLine(rawBR, origin: tr, axis: axes.v)  // 右上の真下
        let bl = WindowCalculator.projectOntoLine(br, origin: tl, axis: axes.v)     // 左上の真下・右下と同じ下端

        let size = WindowCalculator.size(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, planeNormal: normal)
        XCTAssertNotNil(size)
        XCTAssertEqual(size!.width, 1.0, accuracy: tolerance)
        XCTAssertEqual(size!.height, 1.6, accuracy: tolerance)
        XCTAssertEqual(tl.y, tr.y, accuracy: 1e-6)   // 上辺は水平
        XCTAssertEqual(bl.y, br.y, accuracy: 1e-6)   // 下辺は水平
        XCTAssertEqual(tl.x, bl.x, accuracy: 1e-6)   // 左辺は鉛直
        XCTAssertEqual(tr.x, br.x, accuracy: 1e-6)   // 右辺は鉛直
    }
}
