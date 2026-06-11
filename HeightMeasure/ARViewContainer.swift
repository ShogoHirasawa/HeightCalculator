import SwiftUI
import RealityKit
import ARKit

/// UIViewRepresentable（§9）。ARView を生成し §3 のセッション設定を適用する。
struct ARViewContainer: UIViewRepresentable {
    let viewModel: MeasureViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        // 水平（床）に加え、レティクルを壁にも沿わせるため垂直面も検出する（§7.4）。
        // ただし底点の確定・計測ボタンの有効化は水平面のみ（§5.1 / §7.4）。
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none

        arView.session.delegate = viewModel
        viewModel.attach(arView: arView)
        arView.session.run(configuration)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
