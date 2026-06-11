import Foundation
import RealityKit
import ARKit
import UIKit
import simd
import Combine

/// 底点選択中（.waitingBase）に、画面中央が床を捉えているかの状態（§7.4 ガイドUI）。
/// - off: 床に当たっていない（壁・空中など）→ 計測ボタン無効
/// - approximate: 推定平面・無限延長にのみ当たっている（遠方/未検出）→ おおよそ
/// - locked: 実検出された床（.existingPlaneGeometry）に当たっている → 正確
enum ReticleState {
    case off
    case approximate
    case locked
}

/// 共有シート（§7.7）に渡す撮影画像。`.sheet(item:)` 用に Identifiable。
struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 仕様書 §6・§5・§8 を担う ObservableObject 兼 ARSessionDelegate（§9）。
@MainActor
final class MeasureViewModel: NSObject, ObservableObject, ARSessionDelegate {

    // MARK: - Published 状態
    @Published private(set) var state: MeasureState = .initializing
    @Published private(set) var measurements: [Measurement] = []
    /// エラー表示中はバナーをこの文言・赤背景にする（§8）。
    @Published private(set) var errorMessage: String? = nil
    /// 直近に追加した行のハイライト対象（§7.3）。
    @Published private(set) var highlightedID: UUID? = nil
    /// 床ロック状態（§7.4）。計測ボタンの有効判定に使う（水平の床のみ locked/approximate）。
    @Published private(set) var reticleState: ReticleState = .off
    /// レティクルが何らかの面（床/壁）に乗っているか（§7.4）。2Dフォールバック表示の判定に使う。
    @Published private(set) var isReticleOnSurface: Bool = false
    /// ライブガイド（§7.6）。底点 `B` を画面に投影した点。`.waitingTarget` 中のみ非nil。
    @Published private(set) var projectedBase: CGPoint? = nil
    /// ライブガイド（§7.6）。`B` の真上・高さ `H` の終点 `T=(Bx,By+H,Bz)` を画面に投影した点。
    /// 終点を鉛直線上に拘束するため、レティクル（画面中央）ではなくこの点に線・終点マーカーを描く。
    @Published private(set) var projectedTarget: CGPoint? = nil
    /// ライブガイド（§7.6）。常時表示する鉛直リファレンス線の上端（`B` の真上）を投影した点。
    /// カメラを上げる前（角度が無効）でも鉛直ガイドを出すために使う。
    @Published private(set) var projectedReferenceTop: CGPoint? = nil
    /// ライブガイド（§7.6）。現在のカメラ角度から算出した暫定の高さ（m）。無効角度のとき nil。
    @Published private(set) var liveHeightMeters: Double? = nil
    /// 撮影・共有（§7.7）。非nilの間、共有シートを表示する。dismiss 時に nil へ戻す。
    @Published var shareItem: ShareItem? = nil
    /// 撮影フロー（§7.7）。ステップ2: フレーミング（撮影）モードか。
    @Published private(set) var captureMode: Bool = false
    /// 撮影フロー（§7.7）。ステップ3: 撮影済み画像（非nilでプレビュー＋保存/共有を表示）。
    @Published var capturedImage: UIImage? = nil
    /// 撮影ガイド（§7.7）。最新計測の底点が画角（余白付き）に入っているか。
    @Published private(set) var baseInFrame: Bool = false
    /// 撮影ガイド（§7.7）。最新計測の終点が画角（余白付き）に入っているか。
    @Published private(set) var targetInFrame: Bool = false
    /// 撮影フロー（§7.7）。「写真に保存しました」トーストの表示。
    @Published private(set) var savedToastVisible: Bool = false

    // MARK: - AR 参照・内部状態
    private weak var arView: ARView?
    /// 確定待ちの底点アンカー（やり直しで削除する対象）。
    private var baseAnchor: AnchorEntity?
    /// クリアで削除する全エンティティ（底点マーカー・鉛直線）。
    private var sceneAnchors: [AnchorEntity] = []
    private var baseWorldPosition: SIMD3<Float>?
    private var nextIndex: Int = 1
    private var errorToken: Int = 0
    private var highlightToken: Int = 0
    private var savedToastToken: Int = 0
    /// 床に沿って配置するレティクル本体（§7.4）。白いリング＋中心点を、十字が指す床位置に
    /// 置き、床面に寝かせて表示する（見る角度で楕円に傾く＝純正「計測」アプリ風）。
    private var reticleEntity: Entity?
    /// 撮影中はレティクルを隠す（§7.7）。スナップショットに照準リングを写さないため。
    private var suppressReticle = false

    // MARK: - エラー文言（§8）
    private let messageFloorNotFound = "床が検出できません。地面を映してから再度お試しください"
    private let messageTooSteep = "角度が急すぎます。少し下げて対象に合わせてください"
    private let messageTooLow = "対象が低すぎます。底点より上を狙ってください"
    private let messageTracking = "動かさずに少し待ってください（トラッキング調整中）"

    // MARK: - セットアップ
    func attach(arView: ARView) {
        self.arView = arView
        arView.session.delegateQueue = .main
        setupReticleEntity(in: arView)
    }

    /// 床に沿うレティクル（白いリング＋中心点）を1つだけ生成しておく（§7.4）。
    private func setupReticleEntity(in arView: ARView) {
        let anchor = AnchorEntity(world: .zero)
        let parent = Entity()

        // 閉じたトーラス＋球なので、UnlitMaterial の白で表裏問わずリングとして見える。
        let material = UnlitMaterial(color: .white)
        let ring = ModelEntity(mesh: Self.makeRingMesh(), materials: [material])
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.004), materials: [material])
        parent.addChild(ring)
        parent.addChild(dot)
        parent.isEnabled = false

        anchor.addChild(parent)
        arView.scene.addAnchor(anchor)
        reticleEntity = parent
    }

    /// 床に寝かせて表示するリング（トーラス）メッシュを生成する。XZ平面に水平に作る。
    private static func makeRingMesh(majorRadius R: Float = 0.045, tubeRadius r: Float = 0.0035,
                                     majorSeg: Int = 48, minorSeg: Int = 10) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0..<majorSeg {
            let u = Float(i) / Float(majorSeg) * 2 * .pi
            let cu = cos(u); let su = sin(u)
            for j in 0..<minorSeg {
                let v = Float(j) / Float(minorSeg) * 2 * .pi
                let cv = cos(v); let sv = sin(v)
                positions.append([(R + r * cv) * cu, r * sv, (R + r * cv) * su])
                normals.append([cv * cu, sv, cv * su])
            }
        }
        for i in 0..<majorSeg {
            for j in 0..<minorSeg {
                let i1 = (i + 1) % majorSeg
                let j1 = (j + 1) % minorSeg
                let a = UInt32(i * minorSeg + j)
                let b = UInt32(i1 * minorSeg + j)
                let c = UInt32(i1 * minorSeg + j1)
                let d = UInt32(i * minorSeg + j1)
                indices += [a, b, c, a, c, d]
            }
        }
        var descriptor = MeshDescriptor(name: "reticleRing")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: R)
    }

    // MARK: - ボタン操作

    /// 計測ボタン押下（§5・§6）。
    func measureTapped() {
        guard state.isMeasureButtonEnabled else { return }
        guard let arView else { return }

        // トラッキング不良チェック（§8）
        guard let frame = arView.session.currentFrame else {
            showError(messageTracking)
            return
        }
        switch frame.camera.trackingState {
        case .normal:
            break
        default:
            showError(messageTracking)
            return
        }

        switch state {
        case .initializing:
            return
        case .waitingBase:
            captureBase(arView)
        case .waitingTarget:
            captureTarget(frame: frame)
        }
    }

    /// クリアボタン押下（§7.1-5）。
    func clearTapped() {
        guard let arView else { return }
        for anchor in sceneAnchors {
            arView.scene.removeAnchor(anchor)
        }
        sceneAnchors.removeAll()
        baseAnchor = nil
        baseWorldPosition = nil
        measurements.removeAll()
        nextIndex = 1
        highlightedID = nil
        // 水平面は検出済みのため waitingBase に戻す。
        if state != .initializing {
            state = .waitingBase
        }
    }

    /// やり直しボタン押下（§7.1-6）。.waitingTarget のときのみ有効。
    func redoTapped() {
        guard state == .waitingTarget else { return }
        if let anchor = baseAnchor, let arView {
            arView.scene.removeAnchor(anchor)
            sceneAnchors.removeAll { $0 === anchor }
        }
        baseAnchor = nil
        baseWorldPosition = nil
        state = .waitingBase
    }

    // MARK: - ステップ① 底点の捕捉（§5.1）

    /// 画面中央から指定アラインメントの面へレイキャストする（§5.1）。精度優先の順で試し、
    /// 最初に当たった結果と、それが「正確（実検出面）」かどうかを返す。
    /// 1) `.existingPlaneGeometry`: 実検出された面の範囲内のみ（exact=true）。
    /// 2) `.estimatedPlane`: 特徴点からの推定平面（exact=false）。
    /// 3) `.existingPlaneInfinite`: 検出済み面の無限延長（exact=false）。
    private func raycast(_ arView: ARView,
                         alignment: ARRaycastQuery.TargetAlignment) -> (hit: ARRaycastResult, exact: Bool)? {
        if let hit = arView.raycast(from: arView.center, allowing: .existingPlaneGeometry, alignment: alignment).first {
            return (hit, true)
        }
        for target: ARRaycastQuery.Target in [.estimatedPlane, .existingPlaneInfinite] {
            if let hit = arView.raycast(from: arView.center, allowing: target, alignment: alignment).first {
                return (hit, false)
            }
        }
        return nil
    }

    private func captureBase(_ arView: ARView) {
        // 底点は必ず水平の床に取る（§5.1）。
        guard let hit = raycast(arView, alignment: .horizontal)?.hit else {
            showError(messageFloorNotFound)
            return
        }
        let t = hit.worldTransform
        let base = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        baseWorldPosition = base
        placeBaseMarker(at: base)
        state = .waitingTarget
    }

    // MARK: - 面に沿うレティクルの更新（§7.4）
    /// 毎フレーム、底点選択中（.waitingBase）のみ面（床/壁）へレイキャストし、レティクルを
    /// その面に沿って配置する。床（水平）に当たった時だけ reticleState を locked/approximate にし、
    /// 壁（垂直）や未ヒットは off（計測ボタン無効）とする。
    private func updateReticle() {
        guard !suppressReticle else {
            reticleEntity?.isEnabled = false
            return
        }
        guard state == .waitingBase, let arView, let result = raycast(arView, alignment: .any) else {
            if reticleState != .off { reticleState = .off }
            if isReticleOnSurface { isReticleOnSurface = false }
            reticleEntity?.isEnabled = false
            return
        }
        // 面のワールド変換（位置＋向き）をそのまま適用し、床なら寝かせ、壁なら立てて配置する。
        reticleEntity?.transform = Transform(matrix: result.hit.worldTransform)
        reticleEntity?.isEnabled = true
        if !isReticleOnSurface { isReticleOnSurface = true }

        // 床（水平面）のときのみ計測可能。壁（垂直）は off。
        let isFloor = result.hit.targetAlignment == .horizontal
        let newState: ReticleState = isFloor ? (result.exact ? .locked : .approximate) : .off
        if newState != reticleState { reticleState = newState }
    }

    // MARK: - ライブガイドの更新（§7.6）
    /// 毎フレーム、対象捕捉中（.waitingTarget）のみ、現在のカメラ角度から暫定の高さを計算し、
    /// 底点の画面投影とともに公開する。OverlayView 側で点線・数値・延長線を描画する。
    private func updateGuide(frame: ARFrame) {
        guard state == .waitingTarget, let base = baseWorldPosition, let arView else {
            if liveHeightMeters != nil { liveHeightMeters = nil }
            if projectedBase != nil { projectedBase = nil }
            if projectedTarget != nil { projectedTarget = nil }
            if projectedReferenceTop != nil { projectedReferenceTop = nil }
            return
        }
        let mat = frame.camera.transform
        let camera = SIMD3<Float>(mat.columns.3.x, mat.columns.3.y, mat.columns.3.z)
        let forward = simd_normalize(-SIMD3<Float>(mat.columns.2.x, mat.columns.2.y, mat.columns.2.z))
        let height = HeightCalculator.height(camera: SIMD3<Double>(camera),
                                             forward: SIMD3<Double>(forward),
                                             base: SIMD3<Double>(base))
        // 見下ろし（カメラより低い対象）でも数値を出す。負の高さ（底点より下を狙った）だけ除外。
        let validHeight = (height ?? -1) > 0 ? height : nil
        liveHeightMeters = validHeight
        projectedBase = arView.project(base)
        // 終点は B の鉛直線上（高さ H）に拘束する。これにより左右に振れても線は常に垂直。
        if let validHeight {
            projectedTarget = arView.project(base + SIMD3<Float>(0, Float(validHeight), 0))
        } else {
            projectedTarget = nil
        }
        // 鉛直リファレンス線の上端。数値が出ない極端な角度でも線を常時表示するため、
        // 暫定高さ＋余白か最低0.6mのうち高い方まで伸ばす。
        let refHeight = max(Float(validHeight ?? 0) + 0.3, 0.6)
        projectedReferenceTop = arView.project(base + SIMD3<Float>(0, refHeight, 0))
    }

    // MARK: - ステップ② 対象の捕捉と高さ算出（§5.2）
    private func captureTarget(frame: ARFrame) {
        guard let base = baseWorldPosition else { return }

        let T = frame.camera.transform
        let camera = SIMD3<Float>(T.columns.3.x, T.columns.3.y, T.columns.3.z)
        let forward = simd_normalize(-SIMD3<Float>(T.columns.2.x, T.columns.2.y, T.columns.2.z))

        // 有効条件のチェック（§5.2 / §8）
        let f_h = (forward.x * forward.x + forward.z * forward.z).squareRoot()
        if f_h < Float(HeightCalculator.minHorizontalForward) {
            showError(messageTooSteep)
            return
        }

        guard let H = HeightCalculator.height(camera: SIMD3<Double>(camera),
                                              forward: SIMD3<Double>(forward),
                                              base: SIMD3<Double>(base)) else {
            showError(messageTooSteep)
            return
        }
        // 見下ろしでも測れるが、底点と同じか下（H<=0）は高さとして無効。
        guard H > 0 else {
            showError(messageTooLow)
            return
        }

        drawVerticalLine(from: base, height: Float(H))

        let measurement = Measurement(id: UUID(), index: nextIndex, heightMeters: H, base: base)
        nextIndex += 1
        measurements.insert(measurement, at: 0)
        highlight(measurement.id)

        baseAnchor = nil      // この計測は確定（マーカーは残す）。
        state = .waitingBase
    }

    // MARK: - AR 描画
    /// 純正「計測」アプリ風の白いポイント（床に寝かせた白リング＋中心の白い点）を底点に置く。
    private func placeBaseMarker(at position: SIMD3<Float>) {
        guard let arView else { return }
        let anchor = AnchorEntity(world: position)
        let white = UnlitMaterial(color: .white)
        let ring = ModelEntity(mesh: Self.makeRingMesh(majorRadius: 0.03, tubeRadius: 0.003), materials: [white])
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.006), materials: [white])
        anchor.addChild(ring)
        anchor.addChild(dot)
        arView.scene.addAnchor(anchor)
        baseAnchor = anchor
        sceneAnchors.append(anchor)
    }

    private func drawVerticalLine(from base: SIMD3<Float>, height: Float) {
        guard let arView, height > 0 else { return }
        let anchor = AnchorEntity(world: base + SIMD3<Float>(0, height / 2, 0))
        let box = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.005, height, 0.005)),
            materials: [UnlitMaterial(color: .white)]   // 純正Measureに合わせ白で統一
        )
        anchor.addChild(box)
        arView.scene.addAnchor(anchor)
        sceneAnchors.append(anchor)
    }

    // MARK: - 撮影フロー（§7.7） ステップ②撮影 → ③保存/共有

    /// ステップ② 撮影（フレーミング）モードに入る。照準リングは隠す。
    func enterCaptureMode() {
        guard !measurements.isEmpty else { return }
        captureMode = true
        suppressReticle = true
        reticleEntity?.isEnabled = false
    }

    /// 撮影モードを抜ける（キャンセル）。
    func exitCaptureMode() {
        captureMode = false
        suppressReticle = false
        baseInFrame = false
        targetInFrame = false
    }

    /// シャッター: ARビューを撮影し、各計測の高さ数値を線の中点に合成して、ステップ③へ。
    func shutter() {
        guard let arView, !measurements.isEmpty else { return }
        let labels: [(point: CGPoint, text: String)] = measurements.compactMap { m in
            let mid = m.base + SIMD3<Float>(0, Float(m.heightMeters) / 2, 0)
            guard let p = arView.project(mid), arView.bounds.contains(p) else { return nil }
            return (p, String(format: "%.2f m", m.heightMeters))
        }
        arView.snapshot(saveToHDR: false) { [weak self] image in
            guard let self else { return }
            DispatchQueue.main.async {
                self.captureMode = false
                self.suppressReticle = false
                guard let image else { return }
                self.capturedImage = Self.composite(image, labels: labels)
            }
        }
    }

    /// ステップ③ 撮り直す（撮影モードへ戻る）。
    func retake() {
        capturedImage = nil
        enterCaptureMode()
    }

    /// ステップ③ 写真に保存（カメラロール）。
    func saveCaptured() {
        guard let image = capturedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showSavedToast()
    }

    /// ステップ③ 共有シートを表示。
    func shareCaptured() {
        guard let image = capturedImage else { return }
        shareItem = ShareItem(image: image)
    }

    /// ステップ③ プレビューを閉じて通常画面へ戻る。
    func dismissCaptured() {
        capturedImage = nil
    }

    private func showSavedToast() {
        savedToastToken += 1
        let token = savedToastToken
        savedToastVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.savedToastToken == token else { return }
            self.savedToastVisible = false
        }
    }

    /// 撮影モード中、最新計測の底点・終点が画角（余白付き）に入っているかを毎フレーム判定する。
    private func updateFraming() {
        guard captureMode, let arView, let m = measurements.first else {
            if baseInFrame { baseInFrame = false }
            if targetInFrame { targetInFrame = false }
            return
        }
        let frame = arView.bounds.insetBy(dx: 24, dy: 24)   // 余白を持たせて背景も入るように
        let b = arView.project(m.base).map { frame.contains($0) } ?? false
        let t = arView.project(m.base + SIMD3<Float>(0, Float(m.heightMeters), 0)).map { frame.contains($0) } ?? false
        if b != baseInFrame { baseInFrame = b }
        if t != targetInFrame { targetInFrame = t }
    }

    /// スナップショットに数値ピル（白いカプセル＋黒文字、純正Measure風）を合成する。
    private static func composite(_ base: UIImage, labels: [(point: CGPoint, text: String)]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { ctx in
            base.draw(at: .zero)
            let cg = ctx.cgContext
            let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            for label in labels {
                let textSize = (label.text as NSString).size(withAttributes: attrs)
                let padH: CGFloat = 11, padV: CGFloat = 6
                let pillW = textSize.width + padH * 2
                let pillH = textSize.height + padV * 2
                let rect = CGRect(x: label.point.x - pillW / 2, y: label.point.y - pillH / 2,
                                  width: pillW, height: pillH)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                             color: UIColor.black.withAlphaComponent(0.3).cgColor)
                UIColor.white.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: pillH / 2).fill()
                cg.restoreGState()
                (label.text as NSString).draw(at: CGPoint(x: rect.minX + padH, y: rect.minY + padV),
                                              withAttributes: attrs)
            }
        }
    }

    // MARK: - フィードバック
    private func showError(_ message: String) {
        errorToken += 1
        let token = errorToken
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.errorToken == token else { return }
            self.errorMessage = nil
        }
    }

    private func highlight(_ id: UUID) {
        highlightToken += 1
        let token = highlightToken
        highlightedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.highlightToken == token else { return }
            self.highlightedID = nil
        }
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard state == .initializing else { return }
        if anchors.contains(where: { $0 is ARPlaneAnchor }) {
            state = .waitingBase
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateReticle()
        updateGuide(frame: frame)
        updateFraming()
    }
}

// MARK: - 色ユーティリティ
extension UIColor {
    /// 0xRRGGBB 形式の整数から UIColor を生成する。
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
