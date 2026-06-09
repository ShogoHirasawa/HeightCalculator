import SwiftUI

/// SwiftUI オーバーレイ（§7・§9）。レティクル・バナー・結果リスト・3ボタンを描画する。
struct OverlayView: View {
    @ObservedObject var viewModel: MeasureViewModel

    private let highlightColor = Color(UIColor(hex: 0xE1F5EE))
    private let lineColor = Color(UIColor(hex: 0x639922))

    var body: some View {
        ZStack {
            reticle
            VStack(spacing: 0) {
                banner
                Spacer()
                resultList
                buttonBar
            }
        }
    }

    // MARK: - レティクル（§7.1-1）
    private var reticle: some View {
        Image(systemName: "plus")
            .font(.system(size: 32, weight: .regular))
            .foregroundColor(.white)
            .opacity(0.9)
    }

    // MARK: - 上部バナー（§7.1-2 / §7.2 / §8）
    private var banner: some View {
        let isError = viewModel.errorMessage != nil
        let text = viewModel.errorMessage ?? viewModel.state.bannerText
        return Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(isError ? Color(UIColor(hex: 0xA32D2D)) : Color.black.opacity(0.5))
    }

    // MARK: - 結果リスト（§7.1-3 / §7.3）
    private var resultList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(viewModel.measurements) { measurement in
                    Text("計測 \(measurement.index): \(String(format: "%.2f", measurement.heightMeters)) m")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(viewModel.highlightedID == measurement.id ? .black : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            (viewModel.highlightedID == measurement.id ? highlightColor : Color.black.opacity(0.45))
                        )
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
        }
        // 最大5件（約56pt/行）を可視とし、超過分はスクロール。
        .frame(maxHeight: 5 * 56)
    }

    // MARK: - ボタン行（§7.1-4,5,6）
    private var buttonBar: some View {
        HStack(alignment: .center) {
            // やり直し（左）
            Button(action: { viewModel.redoTapped() }) {
                Text("やり直し")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
            }
            .opacity(viewModel.state.isRedoButtonEnabled ? 1.0 : 0.4)
            .disabled(!viewModel.state.isRedoButtonEnabled)

            Spacer()

            // 計測（中央）
            Button(action: { viewModel.measureTapped() }) {
                Text(viewModel.state.buttonLabel)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: UIScreen.main.bounds.width * 0.6, height: 56)
                    .background(lineColor)
                    .cornerRadius(14)
            }
            .opacity(viewModel.state.isMeasureButtonEnabled ? 1.0 : 0.4)
            .disabled(!viewModel.state.isMeasureButtonEnabled)

            Spacer()

            // クリア（右）
            Button(action: { viewModel.clearTapped() }) {
                Text("クリア")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
