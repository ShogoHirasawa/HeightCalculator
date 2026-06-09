# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## Git ワークフロー

- **main ブランチに直接コミットしない**。修正・機能追加は必ずフィーチャーブランチを切って開発する。
- ブランチ名は `fix/〜` または `feat/〜` の形式とする。
- 開発完了後は PR を作成し、ユーザーがテストして承認してからマージする。
- マージ後はフィーチャーブランチを削除する（リモート・ローカル両方）。

## README の管理

- `README.md`（日本語）および `README.en.md`（英語）は**常に本番環境の現状を反映**した状態を維持する。
- マージ時に README の記述と実装に差分があれば、同じコミットまたは直後のコミットで両方の README を更新する。
- 一方の言語のみを更新せず、必ず日本語版・英語版の両方を同期させる。

## 検証ゲート（自律実行の完了条件）

このプロジェクトの「完了」は人間の主観ではなく、以下の機械的ゲートが全て緑であることと定義する。緑になるまで作業を止めず、実装→ビルド→テスト→修正を反復する。

### 完了条件（すべて満たすこと）

1. ビルドがエラーなく成功する（コンパイルが通る）。
2. ユニットテストがすべて成功する。
3. `height_measure_spec.md` の §10「受け入れ基準」の各項目を満たす。

### 実行コマンド
Xcodeプロジェクトは本リポジトリ内に `HeightMeasure` という名前で新規作成する（スキーム名も `HeightMeasure` になる）。変更のたびに次を実行する。

- コンパイル: `xcodebuild build -scheme HeightMeasure -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`
- テスト: `xcodebuild test -scheme HeightMeasure -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`

万一スキーム名が異なる場合のみ `xcodebuild -list` で確認して実値に合わせる。

### このゲートで検証しないこと

- 実機・カメラ・ARKitの実動作（高さ計測の精度）は無人で検証できないため対象外とする。人間が朝に実機で確認する。
- したがってAR動作を対象とする重いE2E/UIテストは追加しない。検証はビルド成功とユニットテストに限定する。

### テスト設計上の制約

- `HeightCalculator`（§5.3 の純関数）は RealityKit / ARKit に依存させない。
- ユニットテストターゲットは**ホストアプリ無し（logic tests）**で構成し、`ARView` を起動せずに `HeightCalculator` を直接テストする。これによりシミュレータでのテストが安定する。
- テストには §10-1 の3ケース（既知入力→期待値、許容誤差 ±0.01m）を必ず含める。

### 完了シグナル

- 上記の完了条件がすべて緑になったら、リポジトリ直下の `.done` に `ALL_GREEN` の一行のみを書き込む。緑でない間は `.done` を作成・更新しない。
