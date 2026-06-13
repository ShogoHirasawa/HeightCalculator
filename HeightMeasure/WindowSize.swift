import Foundation

/// 窓枠の開口寸法（§4.2）。すべてメートル。
struct WindowSize {
    let width: Double     // 幅（上下辺の平均）
    let height: Double    // 高さ（左右辺の平均）
    let diagonal: Double  // 対角線（2本の平均）
}
