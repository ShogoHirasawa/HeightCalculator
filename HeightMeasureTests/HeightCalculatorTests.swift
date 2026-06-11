import XCTest
import simd

/// 仕様書 §10-1 / §5.3 の検証。HeightCalculator は ARKit/RealityKit 非依存のため
/// ホストアプリ無し（logic tests）で ARView を起動せずに検証できる。
/// HeightCalculator.swift をテストターゲットに直接含めるため import は不要。
final class HeightCalculatorTests: XCTestCase {

    private let tolerance = 0.01

    // §10-1 の例: 仰角45°、水平距離3m、カメラ高1.5m → H ≈ 4.5m
    func test_45deg_distance3_cameraHeight1_5() {
        let C = SIMD3<Double>(0, 1.5, 0)
        let B = SIMD3<Double>(0, 0, 3)
        let f = simd_normalize(SIMD3<Double>(0, (0.5).squareRoot(), -(0.5).squareRoot()))
        let H = HeightCalculator.height(camera: C, forward: f, base: B)
        XCTAssertNotNil(H)
        XCTAssertEqual(H!, 4.5, accuracy: tolerance)
    }

    // 仰角30°、水平距離3m、カメラ高1.5m → H = 1.5 + 3*tan30° ≈ 3.232m
    func test_30deg_distance3_cameraHeight1_5() {
        let C = SIMD3<Double>(0, 1.5, 0)
        let B = SIMD3<Double>(0, 0, 3)
        // 仰角30°方向の単位ベクトル: (0, sin30, -cos30)
        let f = SIMD3<Double>(0, 0.5, -(3.0).squareRoot() / 2.0)
        let H = HeightCalculator.height(camera: C, forward: f, base: B)
        XCTAssertNotNil(H)
        XCTAssertEqual(H!, 1.5 + 3.0 * (1.0 / (3.0).squareRoot()), accuracy: tolerance)
    }

    // 斜め配置: C=(1,1.7,1), B=(4,0,5) → 水平距離5m、仰角45° → H = 1.7 + 5 = 6.7m
    func test_lateralOffset_45deg() {
        let C = SIMD3<Double>(1, 1.7, 1)
        let B = SIMD3<Double>(4, 0, 5)
        let f = simd_normalize(SIMD3<Double>(0.3, (0.5).squareRoot(), 0.4))
        // f の水平成分を 45° に合わせるため、水平方向は任意・仰角のみ45°となるよう再構成
        let elevated = SIMD3<Double>(0.6, 1.0, 0.8)        // 水平成分の大きさ1, 鉛直成分1 → tanθ=1
        let fNorm = simd_normalize(elevated)
        let H = HeightCalculator.height(camera: C, forward: fNorm, base: B)
        _ = f
        XCTAssertNotNil(H)
        XCTAssertEqual(H!, 6.7, accuracy: tolerance)
    }

    // カメラより低い対象（見下ろし fy < 0）でも高さを返す。
    // C=(0,1.5,0), B=(0,0,3) で高さ0.5mの点(0,0.5,3)を狙う → H ≈ 0.5m
    func test_belowCamera_returnsValidHeight() {
        let C = SIMD3<Double>(0, 1.5, 0)
        let B = SIMD3<Double>(0, 0, 3)
        let f = simd_normalize(SIMD3<Double>(0, -1, 3))   // 水平距離3、終点高さ0.5へ向かう方向
        let H = HeightCalculator.height(camera: C, forward: f, base: B)
        XCTAssertNotNil(H)
        XCTAssertEqual(H!, 0.5, accuracy: tolerance)
    }

    // 無効条件: 真上付近を向きすぎ（f_h < 0.05）→ nil
    func test_invalid_tooSteep_returnsNil() {
        let C = SIMD3<Double>(0, 1.5, 0)
        let B = SIMD3<Double>(0, 0, 3)
        let f = simd_normalize(SIMD3<Double>(0.01, 1.0, 0.0))   // f_h ≈ 0.01 < 0.05
        XCTAssertNil(HeightCalculator.height(camera: C, forward: f, base: B))
    }
}
