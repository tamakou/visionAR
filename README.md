# visionAR 要件定義

## 1. プロジェクト概要
- **目的**: Apple Vision Pro 向けに、医療現場での参考表示を目的とした AR オーバーレイアプリケーションを実装する。診断・治療・予防を意図せず、常に「非医療機器」であることを表示する。
- **プラットフォーム**: visionOS 26、Apple Vision Pro。
- **開発言語 / フレームワーク**: Swift 6.2、SwiftUI、RealityKit、ARKit (ARKitSession + ImageTrackingProvider)。外部ライブラリは使用しない。

## 2. ステークホルダーと利用想定
- **主要利用者**: 医療従事者が参考情報を視覚化する用途に限定。
- **環境制約**: MDM 管理下での利用も想定し、クラウド送信は禁止。アプリはローカル処理に限定する。

## 3. 機能要件
### 3.1 フォルダアクセスと USDZ 取り込み
- 起動時に「フォルダを接続」ボタンを表示し、Files アプリから任意フォルダを `.fileImporter`（`UTType.folder`）または `UIDocumentPickerViewController` で選択可能にする。
- 選択フォルダはセキュリティスコープ付きブックマークとして永続化し、次回以降は自動でアクセス復元する。
- 許可されたフォルダ配下（サブフォルダ含む）から `.usdz` ファイルを再帰的に列挙し、`Application Support/Models` へ差分コピーする。メタデータ（ファイル名、相対パス、更新日時、ハッシュ）をインデックス化する。
- UI には「フォルダ接続」「インポート（再スキャン）」「モデル一覧」ボタンのみ配置し、モデル選択でロードを開始する。

### 3.2 モデルロードと表示
- `ModelEntity.loadAsync(contentsOf:)` を用いて USDZ を非同期ロードし、読み込みが完了するまでは不可視状態にする。
- シーン階層は `Root Entity` 直下に `CenterNode(Entity)` を置き、モデルを `CenterNode` の子として追加する。初期状態で `ModelEntity.isEnabled = false` とし、姿勢が確定したタイミングで有効化する。
- 追加の手動微調整 UI は実装しない。

### 3.3 画像マーカー追跡
- バンドル資産として `MarkerA`、`MarkerB`、`MarkerC` の 3 枚の参照イメージを登録し、物理サイズ（メートル）を必ず設定する。
- ARKitSession + ImageTrackingProvider を起動し、各画像アンカーの中心ワールド座標を取得する。座標は `MarkerA → p0`、`MarkerB → p1`、`MarkerC → p2` に固定マッピングする。
- 3 点すべてが同時に検出された場合のみ姿勢推定を実行する。1～2 点の検出では待機する。
- 一度配置が完了した後は、自動で再配置を行わず、「再配置」ボタンが押された場合にのみ次の 3 点検出で姿勢を更新する。

### 3.4 姿勢推定ロジック
- 3 点から位置・回転を算出する関数 `poseFromThreePoints` を実装し、以下の仕様を厳守する。
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
  ```
- 数値異常・退化が発生した場合は姿勢適用をスキップし、ユーザーに再計測を促す。

### 3.5 UI 要求
- メインウインドウにフォルダ操作とモデル選択 UI を配置する。
- Immersive Space 内に RealityView を表示し、モデルの表示・非表示と姿勢適用を制御する。
- 画面の目立たない位置に常時「非医療機器」のラベルを表示する。

### 3.6 ログとデータ保護
- 個人情報 (PHI) は収集・保存・送信しない。
- ログは匿名化し、テキストのみを使用。3D モデルや画像データ、座標値をログへ書き出さない。
- ネットワーク通信は行わない。

## 4. 非機能要件
- **性能**: 60fps を目標とし、UI 応答時間を 100ms 未満に保つ。大量のファイル取り込み（100 件以上）でも UI をブロックしない非同期処理を行う。
- **信頼性**: クラッシュやハングを防ぎ、異常系は明確な警告表示で通知する。
- **保守性**: 責務ごとにモジュールを分離する（例: `FolderAccessManager`、`ModelIndexer`、`UsdLoader`、`ImageMarkerTracker`、`PoseEstimator`、`PlacementController`）。
- **拡張性**: 将来的な追加モデル・マーカーに備え、設定やインデックスをデータ駆動で扱える構造を意識する。

## 5. 品質保証 / テスト
- ユニットテストで、既知の三点から計算される姿勢が期待値と一致することを検証する（許容誤差を明記）。
- 実機テストでフォルダ接続、インポート、再配置フローが一連で動作することを確認する。
- 退化ケース（マーカーが一直線上に並ぶ等）で適切にエラー処理され、モデルが表示されないことを確認する。

## 6. 成果物
- visionOS ターゲットを含む Xcode プロジェクト一式。
- `Core/` ディレクトリに主要マネージャークラス群、`UI/` に SwiftUI 画面と RealityView 構築コードを配置する。
- `Assets/ReferenceImages` にマーカー画像と物理サイズ設定を格納する。
- 本 README にセットアップ手順、フォルダ権限の復元方法、再配置手順、既知の制約を追記していく。

## 7. 既知の制約
- 3 マーカーが同時に検出されない場合、モデルは表示されない。
- マーカーの物理サイズが正しく設定されていないと位置精度が低下する。
- 外部ネットワークへデータ送信を行わないため、クラウド連携は提供しない。
- 本アプリは参考表示用途に限定され、医療判断には用いない。
