# HeightMeasure（高さ計測アプリ・三角測量式）

地面に立った状態でスマートフォンをかざし、2階のベランダや窓など「地面より高い対象」までの高さ（地面からの鉛直距離）を計測する iOS 向け AR アプリの最小プロトタイプ。LiDAR を使わず、ARKit のワールドトラッキング（VIO）と重力基準姿勢（`worldAlignment = .gravity`）のみで計測する。

## 計測方法

画面中央のレティクルに合わせ、下部の計測ボタンで 2 点を順に捕捉する。

1. **① 壁の根元（対象の真下の地面）** — 水平面へのレイキャストで底点 `B` を確定。精度優先で `.existingPlaneGeometry`（実検出した床）→ `.estimatedPlane` → `.existingPlaneInfinite`（無限延長）の順に試す。屋内・近距離は正確に、屋外の遠い根元は無限延長で捕捉できる。
2. **② 対象（高さを測りたい点）** — その瞬間のカメラ位置 `C` と前方ベクトル `f` から高さ `H` を算出。

算出式（§5.2）:

```
d    = sqrt((Cx - Bx)^2 + (Cz - Bz)^2)   // 底点までの水平距離
f_h  = sqrt(fx^2 + fz^2)                  // 前方ベクトルの水平成分
H    = (Cy - By) + d * (fy / f_h)         // 地面からの高さ（m）
```

有効条件: `f_h >= 0.05`（真上を向きすぎない）かつ `fy > 0`（対象がカメラより上）。満たさない場合は計測せずエラー表示する。

## 機能

- 1 セッション中に複数回計測し、結果を画面下部のリストに連番で蓄積（最新が最上段）。
- やり直し（`.waitingTarget` のとき直前の底点を破棄）。
- クリア（全結果と AR 上のマーカー・鉛直線を削除し連番リセット）。
- 結果は永続化しない（アプリ終了で破棄）。

## 動作環境

| 項目 | 値 |
|---|---|
| プラットフォーム | iOS（iPhone のみ）|
| 最小対応 OS | iOS 17.0 |
| 言語 / UI | Swift / SwiftUI |
| AR | ARKit + RealityKit（`ARView` を `UIViewRepresentable` で内包）|
| 画面向き | 縦向き固定 |

## プロジェクト構成

| ファイル | 責務 |
|---|---|
| `HeightMeasure/HeightMeasureApp.swift` | アプリエントリポイント |
| `HeightMeasure/ContentView.swift` | AR ビューとオーバーレイの ZStack |
| `HeightMeasure/ARViewContainer.swift` | `ARView` 生成・セッション設定 |
| `HeightMeasure/MeasureViewModel.swift` | 状態管理・計測処理・`ARSessionDelegate` |
| `HeightMeasure/HeightCalculator.swift` | 高さ計算の純関数（§5.3、ARKit 非依存）|
| `HeightMeasure/Measurement.swift` | 計測結果モデル |
| `HeightMeasure/OverlayView.swift` | レティクル・バナー・結果リスト・3 ボタン |
| `HeightMeasure/MeasureState.swift` | 状態 enum と表示文言 |

## ビルド

```sh
xcodebuild build -scheme HeightMeasure \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

> 注: シミュレータの iOS ランタイムが Xcode の同梱バージョンと一致しない環境では `-destination` の解決に失敗することがある。その場合は SDK 指定でコンパイル確認できる:
> `xcodebuild -target HeightMeasure -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`

## テスト

`HeightCalculator` は ARKit/RealityKit 非依存の純関数のため、シミュレータ不要で macOS ネイティブに検証できる（§10-1 の 3 ケースを含む全 5 ケース）:

```sh
swift test
```

シミュレータが利用可能な環境では Xcode のロジックテストでも検証できる:

```sh
xcodebuild test -scheme HeightMeasure \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```
