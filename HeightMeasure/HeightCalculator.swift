import simd

/// 仕様書 §5.3 の純関数。RealityKit / ARKit に依存しない。
/// 入力 C(カメラ位置), f(カメラ前方ベクトル), B(底点) から地面からの高さ H を返す。
/// 無効条件のとき nil を返す。
enum HeightCalculator {

    /// 有効条件のしきい値（§5.2）。
    static let minHorizontalForward: Double = 0.05

    /// - Parameters:
    ///   - camera: カメラ位置 C
    ///   - forward: 正規化済みカメラ前方ベクトル f
    ///   - base: 底点 B（地面）
    /// - Returns: 地面からの高さ H（m）。真上を向きすぎ（`f_h < 0.05`）のとき nil。
    ///   見下ろし（`f.y <= 0`）でも、カメラより低い対象の高さを正しく返す（§5.2）。
    static func height(camera C: SIMD3<Double>,
                       forward f: SIMD3<Double>,
                       base B: SIMD3<Double>) -> Double? {
        let f_h = (f.x * f.x + f.z * f.z).squareRoot()      // 前方ベクトルの水平成分

        // 真上付近を向きすぎていないことだけを要求する（除算の安定性のため）。
        // 仰角の符号（上向き/下向き）は問わない＝カメラより低い対象も測れる。
        guard f_h >= minHorizontalForward else { return nil }

        let dx = C.x - B.x
        let dz = C.z - B.z
        let d = (dx * dx + dz * dz).squareRoot()            // 底点までの水平距離
        let tanTheta = f.y / f_h                             // 仰角の正接（見下ろしで負）
        let H = (C.y - B.y) + d * tanTheta                   // 地面からの高さ
        return H
    }
}
