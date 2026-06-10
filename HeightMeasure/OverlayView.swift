import SwiftUI

/// SwiftUI オーバーレイ（§7・§9）。Apple HIG 準拠の見た目（マテリアル背景・SF Symbols・
/// カプセルボタン）で、レティクル・バナー・床ロックガイド・結果リスト・3 ボタンを描画する。
struct OverlayView: View {
    @ObservedObject var viewModel: MeasureViewModel

    // 配色
    private let accent = Color(UIColor(hex: 0x1D9E75))       // アクセント緑
    private let amber = Color(UIColor(hex: 0xF2A33D))        // おおよそ（黄）
    private let errorRed = Color(UIColor(hex: 0xA32D2D))     // エラー（§8）
    private let highlight = Color(UIColor(hex: 0xE1F5EE))    // 行ハイライト（§7.3）

    var body: some View {
        ZStack {
            // 中央レティクル（§7.1-1 / §7.4）
            reticle
            // 床ロックのステータスチップ（§7.4）。底点選択中のみ、レティクル直下。
            if viewModel.state == .waitingBase {
                floorChip
                    .offset(y: 52)
            }

            VStack(spacing: 0) {
                banner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer()
                resultList
                bottomBar
            }
        }
    }

    // MARK: - レティクル
    private var reticle: some View {
        ZStack {
            Circle()
                .stroke(reticleColor, lineWidth: 3)
                .frame(width: 46, height: 46)
            Circle()
                .fill(reticleColor)
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.35), radius: 2)
        .animation(.easeInOut(duration: 0.15), value: reticleColor)
    }

    private var reticleColor: Color {
        switch viewModel.state {
        case .waitingBase:
            switch viewModel.reticleState {
            case .locked: return accent
            case .approximate: return amber
            case .off: return .white.opacity(0.7)
            }
        case .waitingTarget:
            return .white
        case .initializing:
            return .white.opacity(0.5)
        }
    }

    // MARK: - 床ロックチップ（§7.4）
    private var floorChip: some View {
        let (text, symbol, tint): (String, String, Color)
        switch viewModel.reticleState {
        case .locked:
            (text, symbol, tint) = ("床にロック", "checkmark.circle.fill", accent)
        case .approximate:
            (text, symbol, tint) = ("おおよその床", "circle.dashed", amber)
        case .off:
            (text, symbol, tint) = ("床を探しています", "viewfinder", .white.opacity(0.9))
        }
        return HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(tint, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    // MARK: - 上部バナー（§7.1-2 / §7.2 / §8）
    private var banner: some View {
        let isError = viewModel.errorMessage != nil
        let text = viewModel.errorMessage ?? viewModel.state.bannerText
        return HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "viewfinder")
                .font(.subheadline.weight(.bold))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isError ? AnyShapeStyle(errorRed) : AnyShapeStyle(.ultraThinMaterial))
        )
        .animation(.easeInOut(duration: 0.2), value: isError)
    }

    // MARK: - 結果リスト（§7.1-3 / §7.3）
    private var resultList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(viewModel.measurements) { measurement in
                    let isHighlighted = viewModel.highlightedID == measurement.id
                    HStack(spacing: 10) {
                        Image(systemName: "ruler")
                            .font(.footnote.weight(.semibold))
                        Text("計測 \(measurement.index)")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text(String(format: "%.2f m", measurement.heightMeters))
                            .font(.headline.monospacedDigit())
                    }
                    .foregroundStyle(isHighlighted ? Color.black : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isHighlighted ? AnyShapeStyle(highlight) : AnyShapeStyle(.ultraThinMaterial))
                    )
                    .animation(.easeInOut(duration: 0.2), value: isHighlighted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        // 最大5件（約52pt/行）を可視とし、超過分はスクロール。
        .frame(maxHeight: 5 * 52)
    }

    // MARK: - ボタン行（§7.1-4,5,6）
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 16) {
            sideButton(symbol: "arrow.uturn.backward",
                       label: "やり直し",
                       enabled: viewModel.state.isRedoButtonEnabled,
                       action: { viewModel.redoTapped() })

            measureButton

            sideButton(symbol: "trash",
                       label: "クリア",
                       enabled: true,
                       action: { viewModel.clearTapped() })
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    private var measureButton: some View {
        Button(action: { viewModel.measureTapped() }) {
            HStack(spacing: 8) {
                Image(systemName: measureSymbol)
                Text(viewModel.state.buttonLabel)
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Capsule().fill(isMeasureEnabled ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: isMeasureEnabled ? accent.opacity(0.45) : .clear, radius: 8, y: 4)
        }
        .disabled(!isMeasureEnabled)
        .animation(.easeInOut(duration: 0.15), value: isMeasureEnabled)
    }

    private func sideButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .opacity(enabled ? 1.0 : 0.4)
        .disabled(!enabled)
    }

    // MARK: - 計測ボタンの有効判定（§7.4 床ロックガード）
    private var isMeasureEnabled: Bool {
        switch viewModel.state {
        case .initializing:
            return false
        case .waitingBase:
            // 床を捉えているとき（off 以外）だけ有効にして、壁などの誤選択を防ぐ。
            return viewModel.reticleState != .off
        case .waitingTarget:
            return true
        }
    }

    private var measureSymbol: String {
        switch viewModel.state {
        case .initializing: return "hourglass"
        case .waitingBase: return "scope"
        case .waitingTarget: return "arrow.up"
        }
    }
}
