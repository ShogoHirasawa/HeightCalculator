import SwiftUI

/// 画面全体（§9）。ARViewContainer と OverlayView を ZStack で重ねる。
struct ContentView: View {
    @StateObject private var viewModel = MeasureViewModel()

    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            OverlayView(viewModel: viewModel)
        }
        .statusBarHidden(true)
    }
}
