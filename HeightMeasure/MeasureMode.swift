import Foundation

/// 計測モード（§3）。高さ（屋外・三角測量）と窓枠（屋内・四隅レイキャスト）。
enum MeasureMode: Hashable {
    case height
    case window

    var title: String {
        switch self {
        case .height: return "高さ"
        case .window: return "窓枠"
        }
    }

    var symbol: String {
        switch self {
        case .height: return "arrow.up.and.down"
        case .window: return "macwindow"
        }
    }
}

/// 窓枠モードの状態（§5）。確定済みの四隅の数で進行を表す。
/// 壁の未検出はレティクルのロック状態（reticleState）で表す（ボタンは壁ロック時のみ有効）。
enum WindowState: Equatable {
    case placing(Int)       // 0〜3 点確定済み（次に置くのは n+1 点目）
    case done               // 4点確定

    /// まだ角を置ける段階か（4点未満）。
    var canPlace: Bool {
        if case .placing = self { return true }
        return false
    }

    /// 次に置く角のインデックス（0始まり）。done のときは nil。
    var nextCornerIndex: Int? {
        if case let .placing(n) = self { return n }
        return nil
    }

    /// 四隅のラベル（時計回り: 左上→右上→右下→左下）。
    static let cornerLabels = ["左上", "右上", "右下", "左下"]
}
