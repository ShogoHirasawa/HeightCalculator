import Foundation
import simd

/// 仕様書 §9 の計測結果モデル。
struct Measurement: Identifiable {
    let id: UUID
    let index: Int
    let heightMeters: Double
    /// 底点 `B` のワールド座標（§7.7 撮影時に数値ピルの位置を投影するために保持）。
    let base: SIMD3<Float>
}
