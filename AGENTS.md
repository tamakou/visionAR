# AGENTS.md

## AI開発ルール（医療用 AR オーバーレイアプリ）

### 🧠 基本方針
- **英語で思考し、日本語で出力**すること。
- **最新の Apple 公式ドキュメント / WWDC 情報 / visionOS SDK 仕様**を随時確認し、コード・設計に即時反映すること。
- **Swift 6.2 / visionOS 26 / Xcode 26** を前提とし、**非推奨 API を使用しない**。置き換え候補がある場合は必ず提示する。
- **爆速実装より堅牢性を優先**し、落ちない・詰まらない・再現可能な実装を徹底する（クラッシュ 0、UI フリーズ 0 を目標）。
- **生成前に要件を明文化**（この AGENTS.md を基準）し、ズレがあれば都度ここを更新する。

---

### 🧭 範囲・コンプライアンス（重大）
- 本アプリは**医療機器ではない**。**診断・治療・予防・手術計画・術中ナビ**等の用途は禁止。**参考表示（補助表示）に限定**。
- UI/文言ルール：
  - 使用可：**「参考表示」「ガイド表示」「候補表示」「プレビュー」** 等の補助ニュアンス。
  - 使用禁止：**「診断」「確定」「最適」「ROI（関心領域）」** 等、断定/誘導的・医療機器該当性を高める表現。
  - 初回起動時と設定画面、表示画面下部に**「非医療機器」常時明示**。常時表示がノイズにならないよう小さく固定。
- **PHI/個人情報**：既定で**収集・送信・保存しない**。ログは**匿名化・テキストのみ**。画像・3D・位置データはログに残さない。
- **クラウド送信禁止**（既定）。送信が必要な機能は別途仕様化し、**同意・暗号化・最小化**を満たすこと。
- 法規・院内規程・端末運用（MDM 等）に抵触しない設計を優先。

---

### 📁 ファイル運用ルール
- `backup` フォルダの**利用/参照禁止**（誤用防止）。必要な場合は `backup-YYYYMMDD-<project>` を**手動で作成**し明示運用。
- 既存コードは**安易に流用せず**、**新規生成**を基本。上書き・削除は**確認不要**（この AGENTS.md・`.gitignore`・`.devcontainer` は**削除禁止**）。
- フォルダ選択は **Files からユーザー操作で一度だけ**。**セキュリティスコープ付きブックマーク**で永続化。

---

### 🧩 visionOS 開発ルール
- **RealityKit + SwiftUI** を中核、**ARKitSession + ImageTrackingProvider** を使用。旧式の SceneKit/古い ARKit API は使用しない。
- 表示は **Immersive Space + Window（コントロール最小限）**。**手動微調整 UI は実装しない**（仕様）。
- 60fps 目標。**フリーズ無し**・**UI 応答性 < 100ms** を目安。GC/アセット読み込みは非同期・段階化。

---

### 🗂️ データ取り込み（USDZ 一括インポート）
- 初回起動時「**フォルダを接続**」ボタン → ユーザーが Files で任意フォルダを選択（`UTType.folder`）。**ブックマーク保存**。
- フォルダ配下（**再帰**）の **`.usdz` を列挙**し、`Application Support/Models` に **差分コピー** & インデックス（名前・相対パス・更新時刻・ハッシュ）。
- UI は最小限：**フォルダ接続 / インポート（再スキャン） / モデル一覧 / 再配置**。

---

### 🖼️ 画像マーカー・位置合わせ（唯一の配置手段）
- **3 枚の参照イメージ**を登録：**`MarkerA` / `MarkerB` / `MarkerC`**（**物理サイズ[m]必須**）。
- **画像アンカーの中心ワールド座標**を取得し、**`MarkerA→p0` / `MarkerB→p1` / `MarkerC→p2`** と固定対応。
- **3 点が同時に有効**になったときのみ配置を実行。1～2 点は**待機**。一度配置したら**自動再配置しない**（「再配置」時のみリセット）。
- **モデルは姿勢確定まで非表示**。確定後に表示オン。

**標準ノード構成（厳守）**
Root(Entity)
└─ CenterNode(Entity) ← ここに pose を適用
└─ ModelEntity(USDZ) ← 読み込み直後は isEnabled = false


---

### 📐 姿勢推定の数理仕様（厳密・固定）
- **3 点の中心**を位置、**2 辺の外積**で面法線 `z`、**一辺方向**を `y`、右手系 `x = y × z` を作り、回転 `R=[x y z]` をクォータニオン化。
- 退化（三点がほぼ一直線 / 数値異常）時は**未配置のまま**リトライ指示。

---

```swift
enum PoseError: Error { case degenerateTriangle, invalidVector }

func poseFromThreePoints(_ p0: simd_float3, _ p1: simd_float3, _ p2: simd_float3)
   throws -> (position: simd_float3, orientation: simd_quatf) {

   let center = (p0 + p1 + p2) / 3

   let v01 = p1 - p0
   let v02 = p2 - p0
   let crossZ = simd_cross(v01, v02)
   guard simd_length(crossZ) > 1e-5 else { throw PoseError.degenerateTriangle }

   var z = simd_normalize(crossZ)
   var y = simd_normalize(p0 - p1)
   var x = simd_normalize(simd_cross(y, z))
   guard x.allFinite && y.allFinite && z.allFinite else { throw PoseError.invalidVector }

   let R = simd_float3x3(columns: (x, y, z))
   return (center, simd_quaternion(R))
}

---
実装注意：

画像アンカー中心は ARImageAnchor/ImageTrackingProvider の transform から 平行移動成分を抽出。

MarkerA/B/C の命名 → p0/p1/p2 対応は固定（検出順に依存しない）。

カメラ基準の z 反転は原則行わない（面法線の一貫性重視）。必要時はオプションフラグで。
---
