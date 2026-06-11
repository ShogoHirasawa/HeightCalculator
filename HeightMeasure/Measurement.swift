import Foundation
import simd

/// 仕様書 §9 の計測結果モデル。
struct Measurement: Identifiable {
    let id: UUID
    let index: Int
    let heightMeters: Double
    /// 底点 `B` のワールド座標（§7.6/§7.7 数値ピル位置の投影に使う）。
    let base: SIMD3<Float>
}

/// 高さの表記（§7.6/§7.7）。1m 未満は cm、以上は m（小数2桁）。ライブ・撮影画像で共通利用。
enum HeightFormat {
    static func string(_ meters: Double) -> String {
        meters < 1.0 ? "\(Int((meters * 100).rounded())) cm" : String(format: "%.2f m", meters)
    }
}
