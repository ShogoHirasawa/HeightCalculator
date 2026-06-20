import simd

/// 窓枠サイズ計測の純関数（§4.3）。RealityKit / ARKit に依存しない。
/// 四隅のワールド座標（時計回り: 左上→右上→右下→左下）を、基準平面に投影し
/// 重力基準（水平=幅 / 鉛直=高さ）の軸合わせ長方形として寸法を返す。
///
/// 平面に拘束することで、各隅の奥行き（壁の法線方向）の誤差を吸収し、Z方向にねじれた
/// 四角形による寸法の歪みを取り除く。さらに水平/鉛直軸へ分解し各頂角90度の長方形として
/// 幅・高さを平均化するため、隅の取り位置のばらつきにも強い。
enum WindowCalculator {

    /// 退化（点の重複や極小辺）とみなすしきい値（m）。
    static let minEdge: Double = 0.02

    /// 基準平面内の重力ベース軸（u=水平 / v=鉛直）を返す。
    /// v は重力上方向を平面へ投影したもの、u は n×v（平面内の水平）。
    /// 壁がほぼ水平で鉛直が決められない場合は nil。
    static func planeAxes(normal: SIMD3<Double>,
                          up: SIMD3<Double> = SIMD3<Double>(0, 1, 0)) -> (u: SIMD3<Double>, v: SIMD3<Double>)? {
        guard simd_length(normal) > 1e-9 else { return nil }
        let n = simd_normalize(normal)
        let vRaw = up - simd_dot(up, n) * n
        guard simd_length(vRaw) > 1e-6 else { return nil }
        let v = simd_normalize(vRaw)
        let u = simd_normalize(simd_cross(n, v))
        return (u, v)
    }

    /// origin を通り axis 方向の直線上へ point を射影する（axis 以外の方向の成分は origin に合わせる）。
    /// axis は単位ベクトル前提。窓枠の「同じ高さの水平線上」「真下の鉛直線上」への拘束に使う。
    static func projectOntoLine(_ point: SIMD3<Double>,
                                origin: SIMD3<Double>,
                                axis: SIMD3<Double>) -> SIMD3<Double> {
        origin + simd_dot(point - origin, axis) * axis
    }

    /// - Parameters:
    ///   - TL/TR/BR/BL: 四隅のワールド座標（時計回り: 左上→右上→右下→左下）
    ///   - planeNormal: 基準平面の法線（壁の向き）。nil の場合は四隅の対角から平面を推定する。
    ///   - up: 重力上方向（worldAlignment=.gravity なら (0,1,0)）。平面内の鉛直＝高さ方向に使う。
    /// - Returns: 幅・高さ・対角線。退化している場合は nil。
    static func size(topLeft TL: SIMD3<Double>,
                     topRight TR: SIMD3<Double>,
                     bottomRight BR: SIMD3<Double>,
                     bottomLeft BL: SIMD3<Double>,
                     planeNormal: SIMD3<Double>? = nil,
                     up: SIMD3<Double> = SIMD3<Double>(0, 1, 0)) -> WindowSize? {
        let center = (TL + TR + BR + BL) / 4

        // 基準平面の法線。指定が無ければ四隅の対角ベクトルの外積から推定する。
        let n: SIMD3<Double>
        if let pn = planeNormal, simd_length(pn) > 1e-9 {
            n = simd_normalize(pn)
        } else {
            let cross = simd_cross(BR - TL, BL - TR)
            guard simd_length(cross) > 1e-9 else { return nil }
            n = simd_normalize(cross)
        }

        // 平面内の2D基底を作る。v=鉛直（up を平面へ投影）、u=水平（n×v）。
        let uAxis: SIMD3<Double>
        let vAxis: SIMD3<Double>
        let vRaw = up - simd_dot(up, n) * n
        if simd_length(vRaw) > 1e-6 {
            vAxis = simd_normalize(vRaw)
            uAxis = simd_normalize(simd_cross(n, vAxis))
        } else {
            // 壁がほぼ水平（窓が天井/床面）で重力から軸を決められない場合は上辺方向で代替。
            let edge = TR - TL
            let uRaw = edge - simd_dot(edge, n) * n
            guard simd_length(uRaw) > 1e-9 else { return nil }
            uAxis = simd_normalize(uRaw)
            vAxis = simd_normalize(simd_cross(n, uAxis))
        }

        // 各点を平面内2D座標 (u, v) へ。法線成分は捨てられる＝平面投影。
        func uv(_ p: SIMD3<Double>) -> SIMD2<Double> {
            let d = p - center
            return SIMD2<Double>(simd_dot(d, uAxis), simd_dot(d, vAxis))
        }
        let a = uv(TL), b = uv(TR), c = uv(BR), e = uv(BL)

        // 幅: 上辺・下辺の水平スパンの平均 / 高さ: 左辺・右辺の鉛直スパンの平均（各頂角90度）。
        let width = (abs(b.x - a.x) + abs(c.x - e.x)) / 2
        let height = (abs(a.y - e.y) + abs(b.y - c.y)) / 2

        // 退化チェック（極小・重複）。
        guard width >= minEdge, height >= minEdge else { return nil }

        // 直角長方形なので対角は幅・高さから求める。
        let diagonal = (width * width + height * height).squareRoot()
        return WindowSize(width: width, height: height, diagonal: diagonal)
    }
}
