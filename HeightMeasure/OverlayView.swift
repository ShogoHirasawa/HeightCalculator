import SwiftUI
import UIKit

/// 触覚フィードバック（§7.4）。床にロックした瞬間に軽いハプティクスを出す。
enum Haptics {
    @MainActor static func snap() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }
}

/// 標準の共有シート（§7.7）。保存（カメラロール）も各アプリへの共有もここから行える。
struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// SwiftUI オーバーレイ（§7・§9）。Apple HIG 準拠の見た目（マテリアル背景・SF Symbols・
/// カプセルボタン）で、レティクル・バナー・床ロックガイド・結果リスト・3 ボタンを描画する。
struct OverlayView: View {
    @ObservedObject var viewModel: MeasureViewModel

    // 配色
    private let accent = Color(UIColor(hex: 0x1D9E75))       // アクセント緑
    private let errorRed = Color(UIColor(hex: 0xA32D2D))     // エラー（§8）
    private let guideAccent = Color(UIColor(hex: 0x4285F4))  // 案内イラストに合わせたブルー
    private let guideInk = Color(UIColor(hex: 0x2A2E33))     // 案内ポップアップの本文色（濃いグレー）

    var body: some View {
        ZStack {
            // ステップ1（計測）: 通常の中央レイヤー＋操作UI。撮影・プレビュー中は隠す。
            if viewModel.capturedImage == nil && !viewModel.captureMode {
                centerLayer
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                normalControls
            }

            // 確定した計測の数値ピル（§7.6）。計測後（ステップ1）・撮影中（ステップ2）とも線上に常時表示。
            if viewModel.capturedImage == nil, let overlay = viewModel.measurementOverlay {
                measurementNumber(overlay)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 窓枠の内側塗り（§4.4）。寸法ラベルより下（先）に重ねて計測範囲を明示。
            if viewModel.capturedImage == nil, let quad = viewModel.windowQuad {
                windowFillOverlay(quad)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 窓枠の寸法ラベル（§4.2）。確定後・撮影中とも、幅/高さ/対角を線上に常時表示。
            if viewModel.capturedImage == nil, !viewModel.windowLabels.isEmpty {
                windowLabelsOverlay
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // ステップ2（撮影）: フレーミングガイド＋シャッター。
            if viewModel.captureMode {
                captureOverlay
            }

            // ステップ3（保存/共有）: 撮影画像のプレビュー＋アクション。
            if let image = viewModel.capturedImage {
                capturePreview(image)
            }

            // 窓枠モード開始時の案内ポップアップ（窓の正面に立って計測するよう促す）。
            if viewModel.showWindowGuide {
                windowGuidePopup
            }

            // 高さモード開始時の案内ポップアップ（地面から2階ベランダ等までの測り方を促す）。
            if viewModel.showHeightGuide {
                heightGuidePopup
            }
        }
        // 床にロックした瞬間に軽いハプティクス（§7.4）。状態変化を安定して拾うため最上位に付ける。
        .onChange(of: viewModel.reticleState) { _, newValue in
            if newValue == .locked { Haptics.snap() }
        }
        // 共有シート（§7.7）。
        .sheet(item: $viewModel.shareItem) { item in
            ShareSheet(image: item.image)
        }
    }

    // MARK: - モード開始時の案内ポップアップ（§7）
    /// 窓枠計測は窓の正面（壁に正対）に立つほど四隅の奥行きが安定するため、開始時に立ち位置を案内する。
    private var windowGuidePopup: some View {
        guidePopup(
            imageName: "window_guide",
            symbol: "figure.stand",
            title: "窓の正面に立って計測してください",
            message: "窓のある壁に対してまっすぐ正面に立ち、斜めからではなく正対した状態で窓枠の四隅を計測すると、より正確に測れます。",
            dismiss: { viewModel.showWindowGuide = false }
        )
    }

    /// 高さ計測は地面と対象（2階のベランダ等）の両方が画角に入る距離まで離れて測るため、立ち位置を案内する。
    private var heightGuidePopup: some View {
        guidePopup(
            imageName: "height_guide",
            symbol: "arrow.up.and.line.horizontal.and.arrow.down",
            title: "地面と対象を画角に入れて計測してください",
            message: "建物から少し離れ、地面と計測したい対象（2階のベランダなど）の両方が画面に収まる位置に立つと、地面から対象までの高さを正確に測れます。",
            dismiss: { viewModel.showHeightGuide = false }
        )
    }

    /// 案内ポップアップの共通レイアウト。案内イラストのトンマナ（白カード・濃色文字・ブルー）に合わせる。
    /// 画像（無ければ SF Symbol）＋見出し＋説明＋「はじめる」。
    private func guidePopup(imageName: String, symbol: String, title: String, message: String, dismiss: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 18) {
                // 用意した案内イラストがあればそれを、無ければ SF Symbol をフォールバック表示。
                // イラストは白背景なので、枠も白に揃えてカードとシームレスに馴染ませる。
                Group {
                    if UIImage(named: imageName) != nil {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 52, weight: .regular))
                            .foregroundStyle(guideAccent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(guideInk)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(guideInk.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: dismiss) {
                    Text("はじめる")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(guideAccent))
                }
                .padding(.top, 2)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
            .padding(.horizontal, 36)
        }
        .transition(.opacity)
    }

    // 画面中央レイヤー（レティクル＋ライブガイド）。レイキャスト原点と一致させるため全画面中央。
    private var centerLayer: some View {
        ZStack {
            if show2DReticle {
                reticle
            }
            guideOverlay
        }
    }

    // 操作レイヤー（セーフエリア内）。
    private var normalControls: some View {
        VStack(spacing: 0) {
            banner
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Spacer()
            bottomBar
            modeSwitcher
                .padding(.bottom, 10)
        }
    }

    // 計測モード切替（§3）。下部のセグメント [高さ][窓枠]。
    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach([MeasureMode.height, MeasureMode.window], id: \.self) { m in
                let selected = viewModel.mode == m
                Button(action: { viewModel.setMode(m) }) {
                    HStack(spacing: 6) {
                        Image(systemName: m.symbol)
                        Text(m.title)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? .white : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(selected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .frame(maxWidth: 240)
        .animation(.easeInOut(duration: 0.15), value: viewModel.mode)
    }

    // 確定した計測の数値ピル（純正Measure風：白カプセル＋黒文字）を線の中点に置く（§7.6）。
    private func measurementNumber(_ overlay: MeasurementOverlay) -> some View {
        ZStack {
            numberPill(overlay.text).position(overlay.mid)
        }
    }

    // 窓枠の内側を控えめにグレーアウト（§4.4）。新しい色相は足さず黒の低不透明度で範囲を明示。
    private func windowFillOverlay(_ quad: [CGPoint]) -> some View {
        Path { p in
            guard let first = quad.first else { return }
            p.move(to: first)
            for pt in quad.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
        }
        .fill(Color.black.opacity(0.22))
    }

    // 窓枠の寸法ラベル（幅/高さ/対角）を各位置に置く（§4.2）。
    private var windowLabelsOverlay: some View {
        ZStack {
            ForEach(viewModel.windowLabels) { label in
                numberPill(label.text).position(label.point)
            }
        }
    }

    // 純正Measure風の白カプセル＋黒文字ピル（数値表示の共通部品）。
    private func numberPill(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    /// 2Dレティクルを表示するか。
    /// - 底点選択中: 面へ乗っている時は AR の面リングに任せて隠す。
    /// - 対象捕捉中: 鉛直リファレンス線を出せている間は隠す（鉛直ガイドに注目させる）。
    private var show2DReticle: Bool {
        if viewModel.mode == .window {
            // 角を置ける段階で、壁に乗っていない時だけ2Dフォールバックを出す。
            return viewModel.windowState.canPlace && !viewModel.isReticleOnSurface
        }
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

    /// 純正「計測」アプリ風の表記（共通フォーマッタ）。
    private func formatLive(_ h: Double) -> String { HeightFormat.string(h) }

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

    /// 状態に応じた不透明度。面を捉えていない探索中や初期化中はやや薄く。
    private var reticleOpacity: Double {
        if viewModel.mode == .window { return 0.75 }   // 壁を探している（off）時のみ表示
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

    /// モード別のバナー文言。
    private var bannerText: String {
        if let err = viewModel.errorMessage { return err }
        switch viewModel.mode {
        case .height:
            return viewModel.state.bannerText
        case .window:
            switch viewModel.windowState {
            case .placing(let n):
                let corner = WindowState.cornerLabels[n]
                return "カーテンを避けて、カメラを窓枠の\(corner)角に近づけカーソルをあわせてください（ガラス部には反応しない場合があります）"
            case .done:
                if let s = viewModel.windowResult {
                    return "幅 \(HeightFormat.string(s.width)) × 高さ \(HeightFormat.string(s.height))（対角 \(HeightFormat.string(s.diagonal))）"
                }
                return "計測しました"
            }
        }
    }

    private var banner: some View {
        let isError = viewModel.errorMessage != nil
        let text = bannerText
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

    // MARK: - ボタン行（§7.1-4,5,6）
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 16) {
            sideButton(symbol: "arrow.uturn.backward",
                       label: "やり直し",
                       enabled: viewModel.isRedoEnabled,
                       action: { viewModel.redoTapped() })

            measureButton

            // 撮影できる状態（高さ: 計測済み / 窓枠: 4点確定）のとき「撮影」を出す（§7.7）。
            if viewModel.canCapture {
                sideButton(symbol: "camera",
                           label: "撮影",
                           enabled: true,
                           action: { viewModel.enterCaptureMode() })
            }

            sideButton(symbol: "trash",
                       label: "クリア",
                       enabled: true,
                       action: { viewModel.clearTapped() })
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// 計測ボタンのラベル（モード別）。
    private var measureLabel: String {
        switch viewModel.mode {
        case .height:
            return (viewModel.state == .waitingBase && !viewModel.measurements.isEmpty)
                ? "再計測する" : viewModel.state.buttonLabel
        case .window:
            switch viewModel.windowState {
            case .placing(let n):
                return "\(["①", "②", "③", "④"][n]) \(WindowState.cornerLabels[n])"
            case .done:
                return "計測完了"
            }
        }
    }

    private var measureButton: some View {
        Button(action: { viewModel.measureTapped() }) {
            HStack(spacing: 8) {
                Image(systemName: measureSymbol)
                Text(measureLabel)
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

    // MARK: - 計測ボタンの有効判定（§7.4 面ロックガード）
    private var isMeasureEnabled: Bool {
        switch viewModel.mode {
        case .height:
            switch viewModel.state {
            case .initializing:
                return false
            case .waitingBase:
                // 床を捉えているとき（off 以外）だけ有効にして、壁などの誤選択を防ぐ。
                return viewModel.reticleState != .off
            case .waitingTarget:
                return true
            }
        case .window:
            // 1点目は壁ロック必須。2点目以降は基準平面が確定済みなので壁ロック不要で有効。
            return viewModel.windowState.canPlace
                && (viewModel.isWindowPlaneSet || viewModel.reticleState != .off)
        }
    }

    private var measureSymbol: String {
        switch viewModel.mode {
        case .height:
            switch viewModel.state {
            case .initializing: return "hourglass"
            case .waitingBase: return "scope"
            case .waitingTarget: return "arrow.up"
            }
        case .window:
            return viewModel.windowState == .done ? "checkmark" : "scope"
        }
    }

    // MARK: - ステップ2: 撮影（フレーミング）オーバーレイ（§7.7）
    private var captureOverlay: some View {
        let ready = viewModel.captureReady
        let guideText = viewModel.mode == .height ? "高さ・家の外観を画角に入れて撮影" : "窓枠の全体を画角に入れて撮影"
        return VStack(spacing: 0) {
            // 上部ガイド（文言は最小限。詳細はチップで示す）
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder").font(.subheadline.weight(.bold))
                    Text(guideText)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))

                HStack(spacing: 10) {
                    if viewModel.mode == .height {
                        framingChip(label: "地面", ok: viewModel.baseInFrame)
                        framingChip(label: "ベランダ", ok: viewModel.targetInFrame)
                    } else {
                        framingChip(label: "窓枠", ok: viewModel.windowInFrame)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // 下部: キャンセル（左）＋シャッター（中央）
            ZStack {
                Button(action: { viewModel.shutter() }) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 84, height: 84)
                        Circle().fill(.white).frame(width: 70, height: 70)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .disabled(!ready)
                .opacity(ready ? 1.0 : 0.4)

                HStack {
                    Button(action: { viewModel.exitCaptureMode() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func framingChip(label: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // 判定OKでチップ自体を緑に塗りつぶす（線ではなく面で分かりやすく）。未判定はマテリアル。
        .background(
            Capsule().fill(ok ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial))
        )
        .animation(.easeInOut(duration: 0.15), value: ok)
    }

    // MARK: - ステップ3: 撮影プレビュー＋保存/共有（§7.7）
    private func capturePreview(_ image: UIImage) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)
                HStack(spacing: 14) {
                    previewButton("撮り直す", "arrow.counterclockwise") { viewModel.retake() }
                    previewButton("保存", "square.and.arrow.down") { viewModel.saveCaptured() }
                    previewButton("共有", "square.and.arrow.up") { viewModel.shareCaptured() }
                    previewButton("閉じる", "xmark") { viewModel.dismissCaptured() }
                }
                .padding(.bottom, 8)
            }
            if viewModel.savedToastVisible {
                Text("写真に保存しました")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.7)))
            }
        }
    }

    private func previewButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.ultraThinMaterial))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.white)
        }
    }
}
