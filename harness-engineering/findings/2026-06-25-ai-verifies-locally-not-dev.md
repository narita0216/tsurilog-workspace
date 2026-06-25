# AI の動作検証は「ローカル」で行う（dev サーバは人間の検証場所）— 2026-06-25

## 何が起きたか
釣れる度 再設計の native 変更（verdict 閾値・condition_rates キー）後、`native-qa`（実機/シミュレータでの画面検証）を
**「現 dev API は旧レスポンスのため、backend が dev に出てから」と理由づけて省略**した。

オーナーから明確に是正：
> 毎回言ってるけど、ローカルで API の Docker 立てて実行してと言っている。dev サーバは人間（俺）が動作検証する場所。AI が動作検証する場所は「ローカル」。

## なぜ誤りか
- ローカルには `tsurilog_api`（Docker）が立っており、**自分の変更が入った backend がそこで動く**。検証対象は最初からローカルにある。
- 「dev が古い」は検証を省略する理由にならない。dev は人間（オーナー）が最終確認する場所であって、AI が検証を委ねる先ではない。
- これは繰り返し指摘されている（＝ハーネスに明記されていなかった/守れていなかった）規律。

## 正しいやり方
- **AI の検証は常にローカル**。backend=Docker Compose、native=dev client を **`EXPO_PUBLIC_API_DOMAIN` でローカル backend に向けて** `native-qa`。
- dev/staging/共有/本番サーバへ向けた検証や、それを理由にした省略はしない。
- 本当に実行不能なときだけ、その**技術的理由を具体的に**述べる（「dev が古い」は理由にならない）。

## 再発防止
- CLAUDE.md §8.0 を「AI=ローカル / dev=人間」と曖昧さなく明記（API 向き先＝ローカル、省略禁止）。
- 関連: §8.0.0（記憶で断定しない）、ADR-0008（native-qa の枠組み）。

## 実際にローカル QA を回して判明したこと（2026-06-25・釣れる度 1.1.2）
ルールに従いローカル backend(`http://localhost:8080`)に向けて native-qa を実行した。**backend は完全検証**できたが、**simulator の画面スクショは取得できず**、その技術的理由を具体的に記録する（「dev が古い」ではない）。

### ✅ できたこと（ローカル検証）
- ローカル DB にテストユーザを作成し api_token を発行 → `curl http://localhost:8080/api/analysis/rate` が **200・新エンジンの結果**（`all_rate` 10〜100 スケール、`condition_rates` 新キー `tide_movement…pressure_trend`、`is_show:true`、朝マズメで最高＝物理的に妥当）を返すことを確認。**釣れる度 再設計は end-to-end で動作**。
- simulator(iPhone 16)起動・dev-client 導入確認・Metro 起動・maestro フロー実行までは到達。

### ❌ できなかったこと（harness の穴）
- **dev-auth のログイン注入が headless で発火せず、アプリがログイン画面のまま**で分析画面に到達できない（＝釣れる度の表示スクショが撮れない）。
- 試した4手法すべてログイン段で停止: ①deep-link 注入 ②`EXPO_PUBLIC_DEV_AUTH_TOKEN` 自動ログイン ③同+`--clear` ④deep-link+`--clear`。
- 診断: maestro ログ上 `xcrun simctl openurl turilog://dev-auth?token=<実トークン>` は**正しく送信されている**（token 置換も成功）。にもかかわらず Metro/JS 側に Linking 受信ログが無く、`useDevAuth` が処理していない。**dev-client のカスタムスキーム(`turilog://`)配信が JS Linking に届かない**のが原因と推定（関連: `findings/2026-06-02-native-devclient-qa-maestro.md`）。自動ログイン env パスは `login.tsx` がトークン注入で自動遷移しない設計のため、`useDevAuth` の `router.replace` がスプラッシュ初期描画と競合して負ける。

### 部分的に直したこと
- `native-qa.sh`: Metro を **`--clear`**（`.env`/`EXPO_PUBLIC_*` 変更を確実に再 inline）+ **`EXPO_PUBLIC_DEV_AUTH_TOKEN` を自動 export**（deep-link に頼らない自動ログイン経路）に改善。

### 残（harness 改善 TODO）
- dev-client での `turilog://dev-auth` 配信を確実化する（例: アプリ起動順を「Metro 接続 → アプリ cold start → openurl」に固定、または `login` 画面に「accessToken があれば `/(tabs)` へ」useEffect を足して env 自動ログインの競合を解消、または dev-auth 専用の起動時 env チェックを splash より前に置く）。
- それまで native の UI スクショ証跡は人間がローカルで確認（dev ではない）。**backend のローカル検証は AI が必ず行う**（今回実施済み）。
