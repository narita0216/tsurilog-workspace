# お気に入り(=保存ピン)動線の統合改修と計測 — 2026-06-19

改修指示書「ポイント検索・新規ピン作成・お気に入り登録動線の統合改修」(仕様1〜4)の実装メモ。
native: `feature/point-favorite-flow`、backend: `feature/favorite-metrics`。

## 要点: 「お気に入り」は別概念ではなく `pins`(保存ピン)そのもの

- マスタ点(`resources/ai/fishing-points.json` ≈500件)の★登録も、マップ上の新規ピンも、
  すべて `pins` テーブルの1行として**同列に扱う**。お気に入り専用テーブルは作らない。
- native の ☆トグルは座標一致(`utils/geo-distance.ts` の `isSameSpot`, 既定50m)で
  「この地点が既に保存ピンか」を判定し、未登録→`POST /api/pins`、登録済み→`DELETE`。
- 保存成功トーストは「お気に入りに追加しました。ホームで毎日の釣れる度が見られます」に統一。

## 計測(仕様4)を新テーブルなしで満たせる理由 — ただし2つの落とし穴

管理画面(Laravel Blade admin)の指標は既存テーブルから算出できる。**計測用の二重データソースを足さない**。

| 指標 | 出どころ |
|---|---|
| お気に入り登録数(ユーザー別) | `pins`(`deleted_at IS NULL` の件数=現存) |
| 初回お気に入り登録日 | `pins.created_at` の最小 |
| 登録あり/なし別リピート率 | `operation_logs`(活動日数)× `pins` 有無でセグメント |

### 落とし穴1: 再お気に入りで行が増える(`updateOrCreate` × SoftDeletes)

`RegisterPinController` は `Pin::updateOrCreate(['user_id','lat','lng'], ...)`。
Pin は `SoftDeletes` でグローバルスコープが trashed 行を除外し、かつ `pins` に
**(user_id,lat,lng) の unique 制約は無い**。よって「解除→同じ地点を再登録」は
**ソフト削除行を復活させず、新しい行を作る**。

- **登録数**は `deleted_at IS NULL` で数えれば現存数として正しい(重複アクティブ行は出ない)。
- **初回登録日**は「初めて登録した日」を出したいので、`deleted_at` を問わず最古の
  `created_at` を採る(= raw サブクエリで pins を直接読めばグローバルスコープを回避して trashed も含む)。
  現存行だけの最小だと、解除後の再登録日になってしまう。
- Redash で同じ集計を書くときも上記の使い分けに注意。

### 落とし穴2: `operation_logs` は GET/POST を区別しない

`LogOperation` ミドルウェアは `action = ルートURI`(HTTPメソッド非依存)・1ユーザー×1日でユニーク。
よって `pins`(POST 保存)と `pins`(GET 取得)が同じ `action="pins"` に潰れ、**保存イベントの
回数や「保存か取得か」は operation_logs では分からない**(過去に管理画面で「2回しか利用されてない」
と見えた件の原因)。お気に入り登録の権威データは `pins.created_at`。operation_logs は
「その日活動したか(リピートの母数)」にだけ使う。

## 実装ファイル

- native 仕様1: `components/map/center-pin-placer.tsx`、`app/(tabs)/map.tsx`(中央固定ピン)
- native 仕様2: `components/map/map-search-bar.tsx`(地名フォールバック=`expo-location` の
  `geocodeAsync`。iOS=CLGeocoder/Android=端末標準。**追加有料API不要**。ヒット0件かつ
  「周辺を見る」押下時のみ呼ぶ=検索ごとには呼ばない)
- native 仕様3: `components/map/selected-pin-modal.tsx`(☆トグル)、`app/(tabs)/index.tsx`(空状態ガイド)
- 文言一元管理: `constants/point-flow.ts`(コード修正なしで文言調整可)
- backend 仕様4: `app/Http/Controllers/Admin/AdminDashboardController.php`(セグメント別リピート率)、
  `AdminUserController.php`(登録数・初回日)、`resources/views/admin/{dashboard,users}.blade.php`、
  `tests/Feature/AdminAccessTest.php`(+2ケース)

## 残作業

- native の UI 動作確認(`/native-qa`)が未実施。シミュレータで動線(新規ピン/地名ジャンプ/
  ☆トグル/ホーム空状態)を通す。
- 両ブランチとも push・PR は未(人間が実施)。develop 起点で作成済み。
</content>
</invoke>
