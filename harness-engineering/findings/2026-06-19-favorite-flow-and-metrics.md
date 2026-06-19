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

## native-qa(2026-06-19 実施・成功)

`/native-qa` で仕様1〜3を end-to-end 確認済み(7枚スクショ: `tsurilog-native/qa-artifacts/20260619-030822/`、
コミット `d230983`)。ホーム空状態 → 新規ポイント登録 → 中央固定ピン → ☆お気に入り追加
(成功トースト「お気に入りに追加しました…」)→ 検索フォールバック(渋谷)→ ジオコーディングジャンプ。

### QA で踏んだ落とし穴(再発防止)

1. **native-qa ハーネスは dev API 前提だが、ローカル Docker でも回せる。**
   `EXPO_PUBLIC_API_DOMAIN` はビルド時でなく **JS バンドル時**に展開されるので、`.env` を
   `http://localhost:8080`(ローカル API のポート)に書き換えて Metro 再起動すれば
   **ネイティブ再ビルド不要**でローカル backend に向く(iOS sim は host の localhost に到達可)。
   テストユーザは `User::factory()->create(['api_token'=>'<固定36桁>'])` で作り、
   `TSURILOG_DEV_API_TOKEN=<その値>` で渡す。**`survey_completed` は source/visit_plan/frequency の
   3つすべて non-null が条件**(`UserFormatterService`)。1つだけだとアンケートゲートで止まる。
   QA 後は `.env` を dev に戻すこと(`.env` は gitignore なので誤コミットはしないが working tree を戻す)。

2. **ピン保存はメッシュID生成が日本座標前提。非日本座標(例: シミュレータ既定の SF, 経度 -122)だと
   `mesh_500m_id varchar(10)` を超えて `SQLSTATE[22001] value too long` で保存失敗**し、
   アプリには生 SQL が混じった崩れたエラートーストが出る。実ユーザは日本にいるので通常踏まないが、
   GPS ドリフトや海外で踏む**潜在的な堅牢性バグ**。QA では `xcrun simctl location <dev> set 35.628,139.776`
   で日本に寄せて回避。→ backend 側で「日本範囲外なら明示エラー or mesh を nullable 化」を検討(別Issue候補)。

3. **iOS の RN `Modal` は内容を1つの accessibility 要素に統合する**(`accessibilityText` に全テキスト連結、
   子の testID/text は露出しない)。バックドロップ/内容ラッパーの `TouchableOpacity` に `accessible={false}`
   を付けて初めて子ボタンが個別検出可能になる(VoiceOver でも個別読み上げになり実 a11y も改善)。
   マップ上のオーバーレイ(常設ボタン/検索バー)も同様にテキストが露出しないので **testID(`id:`)必須**。

4. **下タブは5個に増えている**(ホーム/マップ/釣行記録/AIアドバイザー/プロフィール)。
   旧 `qa.yaml` の4分割座標(37.5%=マップ)は古い。5分割は 10/30/50/70/90%(マップ=30%)。

## 残作業

- 両コードリポとも push・PR は未(人間が実施)。develop 起点で作成済み。
  native: `feature/point-favorite-flow`(`0196abc`→`f35c797`→`a917765`→`d230983`)、
  backend: `feature/favorite-metrics`(`7176ee8`)。対の PR は本文で相互リンクする。
- 非日本座標のピン保存失敗(上記2)は別 Issue で backend に起票するか検討。
</content>
</invoke>
