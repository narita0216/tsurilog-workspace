# 初心者向けターゲット変更(分析簡素化 / ピンラベル / 最近の釣果ページング)

- 日付: 2026-06-07
- ブランチ: develop 起点の新ブランチ
  - backend: `feature/admin-analytics` … ではなく **`feature/beginner-focus`**(ローカルコミット `6280d5d`、push は owner reomin)
  - native: `feature/beginner-focus`(**push 済み** `f2724b8`)
- 背景: ターゲット/コンセプトを「初心者向け」に変更。魚種別・地点限定など複雑さを削ぎ、シンプルに。

## 実装サマリ
1. **釣果率を魚種非依存に**: `/analysis/rate` の `fish_id` を任意化。未指定で「何か釣れた率」を集計(`GetAnalysisRateController` / `calculateRate` を nullable 対応)。native は `get-rate` から fish_id を外した。
2. **分析画面を1画面に**: 環境/分析タブ・`only_mesh_5km` トグル・「効いている条件 TOP3」を廃止。釣果率グラフ(`HourlyCatchRateChart`)の下に環境カード(`EnvironmentTable`)を配置し、**グラフの横スクラブと環境カルーセルを双方向同期**(EnvironmentTable を `selectedHour`/`onSelectHour` で制御可能化)。**デフォルト選択は現在時刻**。
3. **ダッシュボード再構成**: 魚種選択と「今月の釣行」を廃止。**「お気に入りの釣り場」=保存ピン**(`FavoritePinCard`、タップで分析・鉛筆でラベル編集)。「最近の釣果」は**魚種無関係・最新順・5件+「さらに表示」**(新 `GET /recent_catches` + `useInfiniteQuery`)。「近場の釣り場」は残しつつ魚種非依存に。
4. **ピンのラベル**: `pins.label`(nullable)追加。保存時にクライアントで**最寄り釣り場を自動ラベル**(`nearestFishingPointLabel` ← 既存 `constants/fishing_points.ts` の503件・田ノ浦漁港等)。手動編集は `PUT /pins/{id}/label`(自分のピンのみ)。

## 設計判断
- **釣り場マスタは新設せず**、native に既にある `FISHING_POINTS`(503件, tide_points_500.csv 由来)＋`utils/geo-distance` の最寄り検索を活用してクライアント側で自動ラベル。DB 重複ゼロ・最短。ラベル文字列だけ `pins.label` に保存。
- /dashboard エンドポイントは温存(今は native 未使用)。recent は専用エンドポイントに分離。
- condition_stats / get-dashboard / use-dashboard は dead code として残置(削除はしていない)。

## 確認
- backend: 全201 green。contract-check **404リスク0**(新規 `/recent_catches`・`/pins/{id}/label` は openapi 記載済み。残ドリフトは既存分)。dev pg は `migrate`(pins.label)済み。
- native: `tsc --noEmit` / `expo lint` クリーン(0 error/0 warning)。
- **未実施: `/native-qa`(dev-client 実機/シミュレータでの目視確認)**。UI 変更が大きいため、ビルドして動線確認推奨(特に: 分析のグラフ↔環境カード同期、お気に入りピンのラベル編集、最近の釣果の「さらに表示」)。

## デプロイ手作業
- backend pull → `php artisan migrate`(pins.label)。owner が `feature/beginner-focus` を push。
- native は `feature/beginner-focus` を pull。
