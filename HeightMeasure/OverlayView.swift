import SwiftUI
import UIKit

/// 触覚フィードバック（§7.4）。床にロックした瞬間に軽いハプティクスを出す。
enum Haptics {
    @MainActor static func snap() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }
}

/// SwiftUI オーバーレイ（§7・§9）。Apple HIG 準拠の見た目（マテリアル背景・SF Symbols・
/// カプセルボタン）で、レティクル・バナー・床ロックガイド・結果リスト・3 ボタンを描画する。
struct OverlayView: View {
    @ObservedObject var viewModel: MeasureViewModel

    // 配色
    private let accent = Color(UIColor(hex: 0x1D9E75))       // アクセント緑
    private let errorRed = Color(UIColor(hex: 0xA32D2D))     // エラー（§8）
    private let highlight = Color(UIColor(hex: 0xE1F5EE))    // 行ハイライト（§7.3）

    var body: some View {
        ZStack {
            // 画面中央レイヤー（レティクル＋ライブガイド）。レイキャスト原点と一致させるため
            // セーフエリアを無視してフルスクリーン中央に置く。
            ZStack {
                // 2Dレティクル（フォールバック）。面に沿うリングは AR 空間側で描画するため、
                // 何らかの面に乗っている底点選択中は 2D を隠す。
                if show2DReticle {
                    reticle
                }
                // ライブガイド（§7.6）：地面〜レティクル間の点線・数値・延長線。
                guideOverlay
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 操作レイヤー（セーフエリア内）。
            VStack(spacing: 0) {
                banner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer()
                resultList
                bottomBar
            }
        }
        // 床にロックした瞬間に軽いハプティクス（§7.4）。状態変化を安定して拾うため最上位に付ける。
        .onChange(of: viewModel.reticleState) { _, newValue in
            if newValue == .locked { Haptics.snap() }
        }
    }

    /// 2Dレティクルを表示するか。
    /// - 底点選択中: 面へ乗っている時は AR の面リングに任せて隠す。
    /// - 対象捕捉中: 鉛直リファレンス線を出せている間は隠す（鉛直ガイドに注目させる）。
    private var show2DReticle: Bool {
        switch viewModel.state {
        case .waitingBase:
            return !viewModel.isReticleOnSurface
        case .waitingTarget:
            return viewModel.projectedBase == nil || viewModel.projectedReferenceTop == nil
        case .initializing:
            return true
        }
    }

    // MARK: - ライブガイド（§7.6）
    /// 鉛直リファレンス線（地面→上端）は `.waitingTarget` に入った時点から**常時**表示する。
    /// 角度が有効（対象がカメラより上）になった時だけ、鉛直線上の終点マーカーと数値を重ねる。
    /// 終点を `B` の鉛直線上に拘束しているため、左右にパンしてもガイドは常に垂直。
    private var guideOverlay: some View {
        GeometryReader { _ in
            if viewModel.state == .waitingTarget,
               let pb = viewModel.projectedBase,
               let top = viewModel.projectedReferenceTop {
                // 有効時は終点まで、無効時（カメラ未上昇）はリファレンス上端まで線を引く。
                let lineEnd = viewModel.projectedTarget ?? top
                ZStack {
                    // 鉛直線（純正Measure風：白い実線）
                    Path { p in p.move(to: pb); p.addLine(to: lineEnd) }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .shadow(color: .black.opacity(0.4), radius: 1)

                    // 角度が有効なときのみ、終点マーカー＋数値（鉛直線上の高さ H の点）
                    if let pt = viewModel.projectedTarget, let h = viewModel.liveHeightMeters {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white).frame(width: 6, height: 6))
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .position(pt)
                        // 純正Measure風：白いピル＋濃い文字
                        Text(formatLive(h))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .position(CGPoint(x: (pb.x + pt.x) / 2, y: (pb.y + pt.y) / 2))
                    }
                }
            }
        }
    }

    /// 純正「計測」アプリ風の表記。1m 未満は cm、以上は m（小数2桁）。
    private func formatLive(_ h: Double) -> String {
        h < 1.0 ? "\(Int((h * 100).rounded())) cm" : String(format: "%.2f m", h)
    }

    // MARK: - 2Dレティクル（床非ヒット時・対象捕捉時のフォールバック）
    private var reticle: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 2.5)
                .frame(width: 32, height: 32)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
        }
        .opacity(reticleOpacity)
        .shadow(color: .black.opacity(0.4), radius: 2)
    }

    /// 状態に応じた不透明度。床を捉えていない探索中や初期化中はやや薄く。
    private var reticleOpacity: Double {
        switch viewModel.state {
        case .initializing:
            return 0.5
        case .waitingBase:
            return 0.75   // 床を探している（off）状態でのみ表示されるため薄め
        case .waitingTarget:
            return 1.0
        }
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
