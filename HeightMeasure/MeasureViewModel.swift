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

/// 確定した計測の数値ピルを線上に常時表示するための投影情報（§7.6）。
struct MeasurementOverlay {
    let mid: CGPoint   // 線の中点（数値ピルの位置）
    let text: String
}

/// 画面に投影した寸法ラベル（窓枠の幅/高さ/対角など）。§4.2 / §7.7。
struct ProjectedLabel: Identifiable {
    let id = UUID()
    let point: CGPoint
    let text: String
}

/// 仕様書 §6・§5・§8 を担う ObservableObject 兼 ARSessionDelegate（§9）。
@MainActor
final class MeasureViewModel: NSObject, ObservableObject, ARSessionDelegate {

    // MARK: - Published 状態
    @Published private(set) var state: MeasureState = .initializing
    @Published private(set) var measurements: [Measurement] = []
    /// エラー表示中はバナーをこの文言・赤背景にする（§8）。
    @Published private(set) var errorMessage: String? = nil
    /// 確定した計測の数値ピル（§7.6）。waitingBase/撮影中、線の中点に常時表示する。
    @Published private(set) var measurementOverlay: MeasurementOverlay? = nil
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

    // MARK: - 窓枠モード（§3〜§6）
    /// 計測モード（高さ/窓枠）。
    @Published private(set) var mode: MeasureMode = .height
    /// 窓枠モードの進行状態（四隅の確定数）。
    @Published private(set) var windowState: WindowState = .placing(0)
    /// 窓枠の確定結果（4点確定時に算出）。
    @Published private(set) var windowResult: WindowSize? = nil
    /// 窓枠の寸法ラベル（§4.2）。確定後に幅/高さ/対角を画面投影して常時表示する。
    @Published private(set) var windowLabels: [ProjectedLabel] = []
    /// 窓枠の四隅を画面投影した点（時計回り）。確定後に内側を塗る（§4.4）。4点そろう時のみ非nil。
    @Published private(set) var windowQuad: [CGPoint]? = nil
    /// 撮影ガイド（窓枠）。四隅すべてが画角（余白付き）に入っているか。
    @Published private(set) var windowInFrame: Bool = false
    /// 窓枠モードに入った直後に表示する案内ポップアップ（窓の正面に立つよう促す）。
    @Published var showWindowGuide: Bool = false
    /// 高さモードの開始時に表示する案内ポップアップ（地面から対象までの測り方を促す）。
    /// 高さは初期モードのため、起動直後にも表示する。
    @Published var showHeightGuide: Bool = true

    // MARK: - AR 参照・内部状態
    private weak var arView: ARView?
    /// 確定待ちの底点アンカー（やり直しで削除する対象）。
    private var baseAnchor: AnchorEntity?
    /// クリアで削除する全エンティティ（底点マーカー・鉛直線）。
    private var sceneAnchors: [AnchorEntity] = []
    private var baseWorldPosition: SIMD3<Float>?
    private var nextIndex: Int = 1
    private var errorToken: Int = 0
    private var savedToastToken: Int = 0
    /// 窓枠の四隅ワールド座標（時計回り）。最大4点。
    private var windowCorners: [SIMD3<Float>] = []
    /// 窓枠の基準平面（1点目で確定）。点＝最初の角、法線＝壁面の向き。
    /// 2点目以降はこの平面にレイを交差させて取得し、奥行きのばらつきを排除する。
    private var windowPlane: (point: SIMD3<Float>, normal: SIMD3<Float>)?
    /// 窓枠のAR描画（四隅マーカー・辺の線）。クリアで削除する。
    private var windowAnchors: [AnchorEntity] = []
    /// 床に沿って配置するレティクル本体（§7.4）。白いリング＋中心点を、十字が指す床位置に
    /// 置き、床面に寝かせて表示する（見る角度で楕円に傾く＝純正「計測」アプリ風）。
    private var reticleEntity: Entity?
    /// レティクルを載せるアンカー（クリア時に作り直せるよう参照を保持）。
    private var reticleAnchor: AnchorEntity?
    /// 撮影中はレティクルを隠す（§7.7）。スナップショットに照準リングを写さないため。
    private var suppressReticle = false

    // MARK: - エラー文言（§8）
    private let messageFloorNotFound = "床が検出できません。地面を映してから再度お試しください"
    private let messageTooSteep = "角度が急すぎます。少し下げて対象に合わせてください"
    private let messageTooLow = "対象が低すぎます。底点より上を狙ってください"
    private let messageTracking = "動かさずに少し待ってください（トラッキング調整中）"
    private let messageWallNotFound = "壁が検出できません。窓のある壁を映してください"
    private let messageWindowDegenerate = "角の位置がうまく取れません。離れて取り直してください"

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
        reticleAnchor = anchor
    }

    /// レティクルを作り直す（§7.4 バグ修正）。クリアで計測アンカーを消した後、3Dレティクルが
    /// 再描画されず消えることがあるため、アンカーごと作り直してクリーンに復帰させる。
    private func recreateReticle() {
        guard let arView else { return }
        if let reticleAnchor { arView.scene.removeAnchor(reticleAnchor) }
        reticleEntity = nil
        reticleAnchor = nil
        setupReticleEntity(in: arView)
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

    /// 計測ボタン押下（§5・§6・§4）。モードで分岐する。
    func measureTapped() {
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

        switch mode {
        case .height:
            guard state.isMeasureButtonEnabled else { return }
            switch state {
            case .initializing:
                return
            case .waitingBase:
                captureBase(arView)
            case .waitingTarget:
                captureTarget(frame: frame)
            }
        case .window:
            placeWindowCorner(arView)
        }
    }

    /// クリアボタン押下（§7.1-5）。モードで分岐。
    func clearTapped() {
        switch mode {
        case .height:
            clearScene()
            recreateReticle()   // 計測アンカー削除後に3Dレティクルが消えることがあるため作り直す。
            if state != .initializing { state = .waitingBase }
        case .window:
            clearWindow()
            recreateReticle()
        }
    }

    /// AR上の計測エンティティ・結果・数値ピルをすべて消す（単一計測の置換やクリアで使う）。
    private func clearScene() {
        if let arView {
            for anchor in sceneAnchors { arView.scene.removeAnchor(anchor) }
        }
        sceneAnchors.removeAll()
        baseAnchor = nil
        baseWorldPosition = nil
        measurements.removeAll()
        nextIndex = 1
        measurementOverlay = nil
        // レティクル状態をリセット（直後は2Dフォールバックが出るようにし、表示の空白を防ぐ）。
        if isReticleOnSurface { isReticleOnSurface = false }
        if reticleState != .off { reticleState = .off }
    }

    /// やり直しボタン押下（§7.1-6）。
    /// 高さ: .waitingTarget のとき直前の底点を破棄。窓枠: 直前に置いた角を1つ削除。
    func redoTapped() {
        switch mode {
        case .height:
            guard state == .waitingTarget else { return }
            if let anchor = baseAnchor, let arView {
                arView.scene.removeAnchor(anchor)
                sceneAnchors.removeAll { $0 === anchor }
            }
            baseAnchor = nil
            baseWorldPosition = nil
            state = .waitingBase
        case .window:
            removeLastWindowCorner()
        }
    }

    /// やり直しが押せるか（§7.1-6）。
    var isRedoEnabled: Bool {
        switch mode {
        case .height: return state.isRedoButtonEnabled
        case .window: return !windowCorners.isEmpty
        }
    }

    /// 窓枠の基準平面が確定済みか（1点目を置いた後）。2点目以降は壁ロック不要で計測ボタンを有効化する。
    var isWindowPlaneSet: Bool { windowPlane != nil }

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
        // 単一計測（§7.1）: 新しい計測を始める前に、既存の計測（線・マーカー・数値）を消す。
        clearScene()
        let t = hit.worldTransform
        let base = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        baseWorldPosition = base
        baseAnchor = placeMarker(at: base)
        state = .waitingTarget
    }

    // MARK: - 面に沿うレティクルの更新（§7.4）
    /// 毎フレーム、計測対象の面へレイキャストし、レティクルをその面に沿って配置する。
    /// 高さモードでは床（水平）、窓枠モードでは壁（垂直）に当たった時だけ reticleState を
    /// locked/approximate にする（計測ボタンの有効判定に使う）。それ以外は off。
    private func updateReticle() {
        guard !suppressReticle else {
            reticleEntity?.isEnabled = false
            return
        }

        // 窓枠の2点目以降: 基準平面が確定していれば、平面との交点にレティクルを置き常に計測可能にする
        // （壁ロック不要・凹凸/反射の影響を受けない）。
        if mode == .window, windowState.canPlace, let plane = windowPlane, let arView {
            if let raw = intersectRayWithBasePlane(arView, plane: plane) {
                // 実配置と同じ拘束をプレビューにも適用し、見たまま打てるようにする。
                let p = snapWindowCorner(raw, index: windowCorners.count)
                let q = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: plane.normal)   // 壁面へ立てる
                reticleEntity?.transform = Transform(scale: SIMD3<Float>(repeating: 1), rotation: q, translation: p)
                reticleEntity?.isEnabled = true
                if !isReticleOnSurface { isReticleOnSurface = true }
                if reticleState != .locked { reticleState = .locked }
            } else {
                reticleEntity?.isEnabled = false
                if isReticleOnSurface { isReticleOnSurface = false }
                if reticleState != .off { reticleState = .off }
            }
            return
        }

        // モード別の有効区間と、計測可能なアラインメント。
        let active: Bool
        let validAlignment: ARRaycastQuery.TargetAlignment
        switch mode {
        case .height:
            active = (state == .waitingBase)
            validAlignment = .horizontal
        case .window:
            active = windowState.canPlace
            validAlignment = .vertical
        }
        guard active, let arView, let result = raycast(arView, alignment: .any) else {
            if reticleState != .off { reticleState = .off }
            if isReticleOnSurface { isReticleOnSurface = false }
            reticleEntity?.isEnabled = false
            return
        }
        // 面のワールド変換（位置＋向き）をそのまま適用し、床なら寝かせ、壁なら立てて配置する。
        reticleEntity?.transform = Transform(matrix: result.hit.worldTransform)
        reticleEntity?.isEnabled = true
        if !isReticleOnSurface { isReticleOnSurface = true }

        // 計測対象の面（高さ=水平 / 窓枠=垂直）のときのみ計測可能。
        let isValid = result.hit.targetAlignment == validAlignment
        let newState: ReticleState = isValid ? (result.exact ? .locked : .approximate) : .off
        if newState != reticleState { reticleState = newState }
    }

    // MARK: - ライブガイドの更新（§7.6）
    /// 毎フレーム、対象捕捉中（.waitingTarget）のみ、現在のカメラ角度から暫定の高さを計算し、
    /// 底点の画面投影とともに公開する。OverlayView 側で点線・数値・延長線を描画する。
    private func updateGuide(frame: ARFrame) {
        guard mode == .height, state == .waitingTarget, let base = baseWorldPosition, let arView else {
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
        _ = placeMarker(at: base + SIMD3<Float>(0, Float(H), 0))   // 終点（上端）マーカー

        let measurement = Measurement(id: UUID(), index: nextIndex, heightMeters: H, base: base)
        nextIndex += 1
        measurements.insert(measurement, at: 0)

        baseAnchor = nil      // この計測は確定（マーカーは残す）。
        state = .waitingBase
    }

    // MARK: - AR 描画
    /// 純正「計測」アプリ風の白いポイント（白リング＋中心の白い点）を生成し、シーンに追加して返す
    /// （配列への登録は呼び出し側で行う）。
    private func makeMarker(at position: SIMD3<Float>) -> AnchorEntity? {
        guard let arView else { return nil }
        let anchor = AnchorEntity(world: position)
        let white = UnlitMaterial(color: .white)
        let ring = ModelEntity(mesh: Self.makeRingMesh(majorRadius: 0.03, tubeRadius: 0.003), materials: [white])
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.006), materials: [white])
        anchor.addChild(ring)
        anchor.addChild(dot)
        arView.scene.addAnchor(anchor)
        return anchor
    }

    /// 高さ計測の底点・終点マーカー（sceneAnchors 管理）。
    @discardableResult
    private func placeMarker(at position: SIMD3<Float>) -> AnchorEntity? {
        let anchor = makeMarker(at: position)
        if let anchor { sceneAnchors.append(anchor) }
        return anchor
    }

    /// 2点間に白い線（細い直方体）を引く。windowAnchors 管理（窓枠の辺に使用）。
    private func drawWindowLine(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        guard let arView else { return }
        let dir = b - a
        let len = simd_length(dir)
        guard len > 0.0001 else { return }
        let anchor = AnchorEntity(world: (a + b) / 2)
        let box = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.004, len, 0.004)),   // 既定でローカルY方向に長い
            materials: [UnlitMaterial(color: .white)]
        )
        box.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(dir))   // Y軸を辺方向へ
        anchor.addChild(box)
        arView.scene.addAnchor(anchor)
        windowAnchors.append(anchor)
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

    // MARK: - 窓枠モード（§4〜§6）

    /// 計測モードを切り替える（§3）。
    /// トラッキングはリセットしない（高さ計測のワールド座標を保持するため）。窓枠は屋内で改めて
    /// 検出される垂直面への相対計測なので、世界ドリフトの影響を実質受けない。
    func setMode(_ newMode: MeasureMode) {
        guard newMode != mode else { return }
        mode = newMode
        errorMessage = nil
        if newMode == .window {
            clearWindow()
            showWindowGuide = true
        } else {
            showHeightGuide = true
        }
        recreateReticle()
    }

    /// 窓枠の角を1点確定する（§4.1）。
    /// 1点目: 壁（垂直面）へレイキャストし、その点と法線で「基準平面」を確定する。
    /// 2点目以降: 画面中央のレイと基準平面の交点で取得する（壁ロック不要・凹凸や反射の影響を受けない）。
    private func placeWindowCorner(_ arView: ARView) {
        guard windowState.canPlace else { return }

        let corner: SIMD3<Float>
        if windowCorners.isEmpty {
            // 1点目（左上）: 壁の垂直面に当てて基準平面（点＋法線）を固定する。
            guard let hit = raycast(arView, alignment: .vertical)?.hit else {
                showError(messageWallNotFound)
                return
            }
            let t = hit.worldTransform
            corner = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            // raycast 結果の worldTransform の Y 軸が面の法線方向。
            let normal = simd_normalize(SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z))
            windowPlane = (point: corner, normal: normal)
        } else {
            // 2点目以降: 画面中央のレイ × 基準平面の交点を、窓枠の重力水平/鉛直へ拘束する。
            guard let plane = windowPlane,
                  let p = intersectRayWithBasePlane(arView, plane: plane) else {
                showError(messageWallNotFound)
                return
            }
            corner = snapWindowCorner(p, index: windowCorners.count)
        }

        appendWindowCorner(corner)

        // 3点目（右下）を置いた時点で左下は一意に決まる（左上の真下かつ右下と同じ下端）。自動生成して確定する。
        if windowCorners.count == 3 {
            appendWindowCorner(autoBottomLeft())
        }

        if windowCorners.count == 4 {
            // 最後の辺（④→①）を閉じる。
            drawWindowLine(from: windowCorners[3], to: windowCorners[0])
            finalizeWindow()
        } else {
            windowState = .placing(windowCorners.count)
        }
    }

    /// 辺（直前の角と結ぶ）・マーカーを描き、角を配列に追加する。
    private func appendWindowCorner(_ corner: SIMD3<Float>) {
        if let prev = windowCorners.last {
            drawWindowLine(from: prev, to: corner)
        }
        if let marker = makeMarker(at: corner) { windowAnchors.append(marker) }
        windowCorners.append(corner)
    }

    /// 基準平面内の重力ベース軸（u=水平 / v=鉛直）。壁がほぼ水平で鉛直が取れない場合は nil。
    private func windowAxes() -> (u: SIMD3<Float>, v: SIMD3<Float>)? {
        guard let plane = windowPlane,
              let axes = WindowCalculator.planeAxes(normal: SIMD3<Double>(plane.normal)) else { return nil }
        return (SIMD3<Float>(axes.u), SIMD3<Float>(axes.v))
    }

    /// レイ×平面の生交点を窓枠の重力水平/鉛直へ拘束する。
    /// index 1（右上）: 左上と同じ高さ＝左上を通る水平線上（横位置だけ可変）。
    /// index 2（右下）: 右上の真下＝右上を通る鉛直線上（高さだけ可変）。
    /// 軸が取れない場合は拘束せず生交点を返す。
    private func snapWindowCorner(_ p: SIMD3<Float>, index: Int) -> SIMD3<Float> {
        guard let axes = windowAxes() else { return p }
        switch index {
        case 1:
            return projectOntoLine(p, origin: windowCorners[0], axis: axes.u)
        case 2:
            return projectOntoLine(p, origin: windowCorners[1], axis: axes.v)
        default:
            return p
        }
    }

    /// 左下を算出する（左上の真下 かつ 右下と同じ下端）。
    private func autoBottomLeft() -> SIMD3<Float> {
        guard let axes = windowAxes() else { return windowCorners[0] }
        return projectOntoLine(windowCorners[2], origin: windowCorners[0], axis: axes.v)
    }

    /// origin を通り axis 方向の直線上へ p を射影する（`WindowCalculator.projectOntoLine` の Float 版）。
    private func projectOntoLine(_ p: SIMD3<Float>, origin: SIMD3<Float>, axis: SIMD3<Float>) -> SIMD3<Float> {
        origin + simd_dot(p - origin, axis) * axis
    }

    /// 画面中央のレイと基準平面の交点を求める（壁ロック不要の角取得・レティクル表示に使う）。
    private func intersectRayWithBasePlane(_ arView: ARView,
                                           plane: (point: SIMD3<Float>, normal: SIMD3<Float>)) -> SIMD3<Float>? {
        guard let ray = arView.ray(through: arView.center) else { return nil }
        let denom = simd_dot(ray.direction, plane.normal)
        guard abs(denom) > 1e-6 else { return nil }
        let t = simd_dot(plane.point - ray.origin, plane.normal) / denom
        guard t > 0 else { return nil }
        return ray.origin + t * ray.direction
    }

    /// 4点確定時に寸法を算出する（§4.2）。基準平面の法線を渡し、平面拘束＋直角長方形で算出する。
    private func finalizeWindow() {
        guard windowCorners.count == 4 else { return }
        let c = windowCorners.map { SIMD3<Double>($0) }
        let normal = windowPlane.map { SIMD3<Double>($0.normal) }
        guard let size = WindowCalculator.size(topLeft: c[0], topRight: c[1],
                                               bottomRight: c[2], bottomLeft: c[3],
                                               planeNormal: normal) else {
            showError(messageWindowDegenerate)
            removeLastWindowCorner()   // 退化: 直前を取り消して再取得させる
            return
        }
        windowResult = size
        windowState = .done
    }

    /// 直前のユーザー操作を1つ取り消す（やり直し）。
    private func removeLastWindowCorner() {
        guard let arView, !windowCorners.isEmpty else { return }
        // 取り消す角の数と、それに伴うアンカー（辺＋マーカー）の数。
        // 4点ある＝3点目（右下）配置で右下と左下(自動)＋閉じ辺まで入った状態。右下からやり直すため
        // 右下・左下の2点と、辺TR-BR/BRマーカー/辺BR-BL/BLマーカー/閉じ辺の5アンカーを取り除く。
        let removeCorners: Int
        let removeAnchors: Int
        if windowCorners.count == 4 {
            removeCorners = 2
            removeAnchors = 5
        } else if windowCorners.count >= 2 {
            removeCorners = 1
            removeAnchors = 2   // 辺＋マーカー
        } else {
            removeCorners = 1
            removeAnchors = 1   // マーカーのみ
        }
        for _ in 0..<min(removeAnchors, windowAnchors.count) {
            let anchor = windowAnchors.removeLast()
            arView.scene.removeAnchor(anchor)
        }
        for _ in 0..<min(removeCorners, windowCorners.count) {
            windowCorners.removeLast()
        }
        if windowCorners.isEmpty { windowPlane = nil }   // 1点目を取り消したら基準平面も破棄
        windowResult = nil
        windowLabels = []
        windowState = .placing(windowCorners.count)
    }

    /// 窓枠の全エンティティ・結果を消す（クリア／モード切替）。
    private func clearWindow() {
        if let arView {
            for anchor in windowAnchors { arView.scene.removeAnchor(anchor) }
        }
        windowAnchors.removeAll()
        windowCorners.removeAll()
        windowPlane = nil
        windowResult = nil
        windowLabels = []
        windowState = .placing(0)
        if isReticleOnSurface { isReticleOnSurface = false }
        if reticleState != .off { reticleState = .off }
    }

    /// 確定後、窓枠の寸法ラベル（幅/高さ/対角）と内側塗り用の四隅投影を毎フレーム更新する（§4.2/§4.4）。
    private func updateWindowLabels() {
        guard mode == .window, capturedImage == nil,
              windowState == .done, windowCorners.count == 4, let arView, let size = windowResult else {
            if !windowLabels.isEmpty { windowLabels = [] }
            if windowQuad != nil { windowQuad = nil }
            return
        }
        let tl = windowCorners[0], tr = windowCorners[1], br = windowCorners[2], bl = windowCorners[3]
        // 内側塗り用: 四隅すべてが投影できるときだけ quad を出す。
        let projected = windowCorners.compactMap { arView.project($0) }
        windowQuad = projected.count == 4 ? projected : nil
        var labels: [ProjectedLabel] = []
        // 幅: 上辺の中点
        if let p = arView.project((tl + tr) / 2) {
            labels.append(ProjectedLabel(point: p, text: "幅 " + HeightFormat.string(size.width)))
        }
        // 高さ: 左辺の中点
        if let p = arView.project((tl + bl) / 2) {
            labels.append(ProjectedLabel(point: p, text: "高さ " + HeightFormat.string(size.height)))
        }
        // 対角: 中心
        if let p = arView.project((tl + tr + br + bl) / 4) {
            labels.append(ProjectedLabel(point: p, text: "対角 " + HeightFormat.string(size.diagonal)))
        }
        windowLabels = labels
    }

    // MARK: - 撮影フロー（§7.7） ステップ②撮影 → ③保存/共有

    /// 撮影できる状態か（高さ: 計測済み / 窓枠: 4点確定）。
    var canCapture: Bool {
        switch mode {
        case .height: return !measurements.isEmpty
        case .window: return windowState == .done
        }
    }

    /// 撮影モードのシャッターが押せるか（対象が画角に入っている）。
    var captureReady: Bool {
        switch mode {
        case .height: return baseInFrame && targetInFrame
        case .window: return windowInFrame
        }
    }

    /// ステップ② 撮影（フレーミング）モードに入る。照準リングは隠す。
    func enterCaptureMode() {
        guard canCapture else { return }
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
        windowInFrame = false
    }

    /// シャッター: ARビューを撮影し、寸法ラベル（と窓枠の内側塗り）を合成してステップ③へ。
    func shutter() {
        guard let arView else { return }
        let viewSize = arView.bounds.size
        let labels = currentCompositeLabels(arView)
        // 窓枠モードでは内側の塗りも合成する。
        let fill: [CGPoint]? = {
            guard mode == .window, windowState == .done, windowCorners.count == 4 else { return nil }
            let q = windowCorners.compactMap { arView.project($0) }
            return q.count == 4 ? q : nil
        }()
        arView.snapshot(saveToHDR: false) { [weak self] image in
            guard let self else { return }
            DispatchQueue.main.async {
                self.captureMode = false
                self.suppressReticle = false
                guard let image else { return }
                self.capturedImage = Self.composite(image, viewSize: viewSize, labels: labels, fill: fill)
            }
        }
    }

    /// 撮影画像に合成する寸法ラベル（モード別）。
    private func currentCompositeLabels(_ arView: ARView) -> [(point: CGPoint, text: String)] {
        switch mode {
        case .height:
            guard let m = measurements.first else { return [] }
            let mid = m.base + SIMD3<Float>(0, Float(m.heightMeters) / 2, 0)
            return arView.project(mid).map { [($0, HeightFormat.string(m.heightMeters))] } ?? []
        case .window:
            return windowLabels.map { (point: $0.point, text: $0.text) }
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

    /// 撮影モード中、対象が画角（余白付き）に入っているかを毎フレーム判定する（モード別）。
    private func updateFraming() {
        guard captureMode, let arView else {
            if baseInFrame { baseInFrame = false }
            if targetInFrame { targetInFrame = false }
            if windowInFrame { windowInFrame = false }
            return
        }
        let frame = arView.bounds.insetBy(dx: 24, dy: 24)   // 余白を持たせて背景も入るように
        switch mode {
        case .height:
            guard let m = measurements.first else {
                if baseInFrame { baseInFrame = false }
                if targetInFrame { targetInFrame = false }
                return
            }
            let b = arView.project(m.base).map { frame.contains($0) } ?? false
            let t = arView.project(m.base + SIMD3<Float>(0, Float(m.heightMeters), 0)).map { frame.contains($0) } ?? false
            if b != baseInFrame { baseInFrame = b }
            if t != targetInFrame { targetInFrame = t }
        case .window:
            // 四隅すべてが画角内かどうか。
            let allIn = windowCorners.count == 4 && windowCorners.allSatisfy { c in
                arView.project(c).map { frame.contains($0) } ?? false
            }
            if allIn != windowInFrame { windowInFrame = allIn }
        }
    }

    /// スナップショットに、窓枠の内側塗り（任意）と数値ピル（白いカプセル＋黒文字）を合成する。
    /// 投影座標はビュー（ポイント）系のため、スナップショット画像サイズとの比 `scale` で位置・寸法を補正する
    /// （これを行わないと数値が画像の隅に小さく描かれる）。
    private static func composite(_ base: UIImage, viewSize: CGSize,
                                  labels: [(point: CGPoint, text: String)],
                                  fill: [CGPoint]? = nil) -> UIImage {
        let scale = viewSize.width > 0 ? base.size.width / viewSize.width : 1
        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { ctx in
            base.draw(at: .zero)
            let cg = ctx.cgContext

            // 窓枠の内側を控えめにグレーアウト（§4.4）。ラベルより先（下）に描く。
            if let fill, fill.count == 4 {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: fill[0].x * scale, y: fill[0].y * scale))
                for p in fill.dropFirst() { path.addLine(to: CGPoint(x: p.x * scale, y: p.y * scale)) }
                path.close()
                UIColor.black.withAlphaComponent(0.22).setFill()
                path.fill()
            }

            let font = UIFont.systemFont(ofSize: 16 * scale, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            for label in labels {
                let center = CGPoint(x: label.point.x * scale, y: label.point.y * scale)
                let textSize = (label.text as NSString).size(withAttributes: attrs)
                let padH = 11 * scale, padV = 6 * scale
                let pillW = textSize.width + padH * 2
                let pillH = textSize.height + padV * 2
                let rect = CGRect(x: center.x - pillW / 2, y: center.y - pillH / 2, width: pillW, height: pillH)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 1 * scale), blur: 3 * scale,
                             color: UIColor.black.withAlphaComponent(0.3).cgColor)
                UIColor.white.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: pillH / 2).fill()
                cg.restoreGState()
                (label.text as NSString).draw(at: CGPoint(x: rect.minX + padH, y: rect.minY + padV),
                                              withAttributes: attrs)
            }
        }
    }

    /// 確定した計測の数値ピル位置（線の中点）を毎フレーム投影して公開する（§7.6 常時表示）。高さモードのみ。
    private func updateMeasurementOverlay() {
        guard mode == .height, let arView, capturedImage == nil, let m = measurements.first else {
            if measurementOverlay != nil { measurementOverlay = nil }
            return
        }
        let midWorld = m.base + SIMD3<Float>(0, Float(m.heightMeters) / 2, 0)
        guard let mid = arView.project(midWorld) else {
            if measurementOverlay != nil { measurementOverlay = nil }
            return
        }
        measurementOverlay = MeasurementOverlay(mid: mid, text: HeightFormat.string(m.heightMeters))
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
        updateMeasurementOverlay()
        updateWindowLabels()
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
