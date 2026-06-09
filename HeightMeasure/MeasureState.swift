import Foundation

/// 仕様書 §6 の状態。
enum MeasureState {
    case initializing
    case waitingBase
    case waitingTarget

    /// §7.2 バナー文言（通常時）。
    var bannerText: String {
        switch self {
        case .initializing:
            return "床（地面）を映してください"
        case .waitingBase:
            return "壁の根元（対象の真下の地面）に照準を合わせて「計測」を押してください"
        case .waitingTarget:
            return "対象（ベランダの縁など）に照準を合わせて「計測」を押してください"
        }
    }

    /// §7.2 計測ボタンラベル。
    var buttonLabel: String {
        switch self {
        case .initializing:
            return "準備中…"
        case .waitingBase:
            return "① 壁の根元を指定"
        case .waitingTarget:
            return "② 高さを計測"
        }
    }

    /// §7.1-4 計測ボタンの有効/無効。
    var isMeasureButtonEnabled: Bool {
        self != .initializing
    }

    /// §7.1-6 やり直しボタンの有効/無効。
    var isRedoButtonEnabled: Bool {
        self == .waitingTarget
    }
}
