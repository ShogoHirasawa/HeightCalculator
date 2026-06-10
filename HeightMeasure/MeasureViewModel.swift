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
    /// 床ロック状態（§7.4）。レティクル色・フロアプレビュー・計測ボタンの有効判定に使う。
    @Published private(set) var reticleState: ReticleState = .off

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
    /// 床に沿って配置するレティクル本体（§7.4）。白いリング＋中心点を、十字が指す床位置に
    /// 置き、床面に寝かせて表示する（見る角度で楕円に傾く＝純正「計測」アプリ風）。
    private var reticleEntity: Entity?

    // MARK: - エラー文言（§8）
    private let messageFloorNotFound = "床が検出できません。地面を映してから再度お試しください"
    private let messageTooSteep = "角度が急すぎます。少し下げて対象に合わせてください"
    private let messageTargetBelow = "対象はスマホより上に合わせてください"
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

    /// 画面中央から水平面へレイキャストする（§5.1）。精度優先の順で試し、最初に当たった結果と
    /// それが「正確（実検出の床）」かどうかを返す。
    /// 1) `.existingPlaneGeometry`: 実検出された床の範囲内のみ。十字が指す“その場の床”に正確に当たる（exact=true）。
    /// 2) `.estimatedPlane`: 特徴点からの推定平面。床がまだ十分検出されていない箇所の保険（exact=false）。
    /// 3) `.existingPlaneInfinite`: 検出済み水平面の無限延長。遠く・浅角の屋外の根元など最後の保険（exact=false）。
    private func raycastFloor(_ arView: ARView) -> (hit: ARRaycastResult, exact: Bool)? {
        if let hit = arView.raycast(from: arView.center, allowing: .existingPlaneGeometry, alignment: .horizontal).first {
            return (hit, true)
        }
        for target: ARRaycastQuery.Target in [.estimatedPlane, .existingPlaneInfinite] {
            if let hit = arView.raycast(from: arView.center, allowing: target, alignment: .horizontal).first {
                return (hit, false)
            }
        }
        return nil
    }

    private func captureBase(_ arView: ARView) {
        guard let hit = raycastFloor(arView)?.hit else {
            showError(messageFloorNotFound)
            return
        }
        let t = hit.worldTransform
        let base = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        baseWorldPosition = base
        placeBaseMarker(at: base)
        state = .waitingTarget
    }

    // MARK: - 床に沿うレティクルの更新（§7.4）
    /// 毎フレーム、底点選択中（.waitingBase）のみ床へレイキャストし、レティクルを床位置へ移動・
    /// 床面に沿って向ける。床に当たらなければ非表示にし、reticleState を更新する。
    private func updateReticle() {
        guard state == .waitingBase, let arView, let result = raycastFloor(arView) else {
            if reticleState != .off { reticleState = .off }
            reticleEntity?.isEnabled = false
            return
        }
        // 床面のワールド変換（位置＋向き）をそのまま適用し、面に寝かせて配置する。
        reticleEntity?.transform = Transform(matrix: result.hit.worldTransform)
        reticleEntity?.isEnabled = true

        let newState: ReticleState = result.exact ? .locked : .approximate
        if newState != reticleState { reticleState = newState }
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
        if forward.y <= 0 {
            showError(messageTargetBelow)
            return
        }

        guard let H = HeightCalculator.height(camera: SIMD3<Double>(camera),
                                              forward: SIMD3<Double>(forward),
                                              base: SIMD3<Double>(base)) else {
            showError(messageTooSteep)
            return
        }

        drawVerticalLine(from: base, height: Float(H))

        let measurement = Measurement(id: UUID(), index: nextIndex, heightMeters: H)
        nextIndex += 1
        measurements.insert(measurement, at: 0)
        highlight(measurement.id)

        baseAnchor = nil      // この計測は確定（マーカーは残す）。
        state = .waitingBase
    }

    // MARK: - AR 描画
    private func placeBaseMarker(at position: SIMD3<Float>) {
        guard let arView else { return }
        let anchor = AnchorEntity(world: position)
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: UIColor(hex: 0x1D9E75), isMetallic: false)]
        )
        anchor.addChild(sphere)
        arView.scene.addAnchor(anchor)
        baseAnchor = anchor
        sceneAnchors.append(anchor)
    }

    private func drawVerticalLine(from base: SIMD3<Float>, height: Float) {
        guard let arView, height > 0 else { return }
        let anchor = AnchorEntity(world: base + SIMD3<Float>(0, height / 2, 0))
        let box = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.005, height, 0.005)),
            materials: [SimpleMaterial(color: UIColor(hex: 0x639922), isMetallic: false)]
        )
        anchor.addChild(box)
        arView.scene.addAnchor(anchor)
        sceneAnchors.append(anchor)
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
