import Foundation

/// 仕様書 §9 の計測結果モデル。
struct Measurement: Identifiable {
    let id: UUID
    let index: Int
    let heightMeters: Double
}
