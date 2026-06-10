import SwiftUI
import RealityKit
import ARKit

/// UIViewRepresentable（§9）。ARView を生成し §3 のセッション設定を適用する。
struct ARViewContainer: UIViewRepresentable {
    let viewModel: MeasureViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none

        arView.session.delegate = viewModel
        viewModel.attach(arView: arView)
        arView.session.run(configuration)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
