import simd

/// 窓枠サイズ計測の純関数（§4.3）。RealityKit / ARKit に依存しない。
/// 四隅のワールド座標（時計回り: 左上→右上→右下→左下）から、幅・高さ・対角線を返す。
enum WindowCalculator {

    /// 退化（点の重複や極小辺）とみなすしきい値（m）。
    static let minEdge: Double = 0.02

    /// - Parameters:
    ///   - topLeft / topRight / bottomRight / bottomLeft: 四隅のワールド座標（時計回り）
    /// - Returns: 幅・高さ・対角線。退化している場合は nil。
    static func size(topLeft TL: SIMD3<Double>,
                     topRight TR: SIMD3<Double>,
                     bottomRight BR: SIMD3<Double>,
                     bottomLeft BL: SIMD3<Double>) -> WindowSize? {
        func d(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { simd_length(a - b) }

        let top = d(TL, TR)
        let bottom = d(BL, BR)
        let left = d(TL, BL)
        let right = d(TR, BR)
        let diag1 = d(TL, BR)
        let diag2 = d(TR, BL)

        let width = (top + bottom) / 2
        let height = (left + right) / 2
        let diagonal = (diag1 + diag2) / 2

        // 退化チェック（極小・重複）。
        guard width >= minEdge, height >= minEdge else { return nil }

        return WindowSize(width: width, height: height, diagonal: diagonal)
    }
}
