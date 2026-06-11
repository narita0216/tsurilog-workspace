# 引き継ぎメモ: 潮データ外部API移行 + 緊急ホットフィックス(2026-06-12)

新セッションはまずこのファイルを読むこと。直近の作業状態・未コミット・意思決定・次の一手をまとめる。

## いま何をしているか(最重要)
本番 `/analysis/rate` が **500**。原因＝**WWO(World Weather Online) marine が潮(tide)を返さなくなった**(`tides:[{}]` 空)。`calculateTideAction` が空データで例外を投げ、env取得→分析API全体が落ちる。

### WWO 調査の確定事実
- WWOの呼び出しは成功(天気/波/水温は返る・errorなし)が、**tide だけ常に空**。tp(1/3/24/none)・座標(相模湾/伊豆/沖縄)・全5日で再現。**コード/パラメータのバグではない**。
- 公式doc: 「tide は Premium Marine ユーザー限定」。本番キー `d7bea2df410148248e3231748260401` は **Pro($10/月, Marine=5 day weather)** だが tide が来ない。トライアル(1〜3月頃)は tide 込みで動いていた → トライアル降格で tide 停止＝「急に取れなくなった」正体。
- **WWO サポートに英語で問い合わせ済み(緊急・返金要求込み)。自動受付返信あり、実回答待ち。**

## 方針(決定済み)
**WWO を捨て、潮は緯度経度ベースの専用APIへ移行。** 2段で進める:
1. **緊急: 500を止める** — env-data を Open-Meteo 化＋潮失敗を握りつぶし(nullable)した実装を、AIブランチから緊急ブランチへ移植(下記)。tid_action は当面 null。
2. **本対応: 潮の動きを復活** — **WorldTides API** で lat/lng から満干/上げ下げを取得し `calculateTideAction` の入力に差し替え。

## ブランチ/未コミット状態(注意)
- **native**: `feature/ai-strategy`(AI機能。まだリリースしない)。
- **backend**: `fix/tide-data-error`(**最新 main 起点の緊急ブランチ**。ユーザー指示で main 起点)。
  - **未コミットで env-data 15ファイルが置いてある**(feature/ai-strategy から `git checkout` で移植したもの)。内容: Open-Meteo化(OpenMeteoClient/GetEnvData/config/openmeteo.php)、tid_type=tide736、**tid_action は WWO のままだが try/catch + tid_action nullable 化で500回避**、env_cache raw値+tide nullable のmigration 2本、関連テスト、phpunit.xml(OPEN_METEO env固定)。
  - ⚠️ **まだローカルでテスト未実行**。ローカル vendor から phpunit(dev依存)が消えていた(`composer install --no-dev` が回った形跡)→ `docker compose exec -w /var/www tsurilog_api composer install`(dev込み)で復元してから `php vendor/bin/phpunit` する必要あり。
  - 次手: テスト緑を確認 → コミット(backendは reomin。push はユーザー)。

## WorldTides 採用メモ(本対応の調査結果)
- lat/lng で `extremes`(満潮/干潮+時刻+潮位) と `heights`(時系列)。FES2014(全球潮汐モデル)+観測点ベース。**WWOの“おまけtide”より専門的で品質上**。内湾(東京湾等)は JMA港別(tide736)が上な場面あり=要実値照合(気象庁潮位表で東京/大阪/那覇を突き合わせ)。
- 料金: 登録時100クレジット無料。月額 $4.99=2万クレジット〜。買い切り $9.99=2万〜。**1リクエスト=1クレジット(extremes/heightsは最大7日分で1)**。mesh×日付キャッシュ前提なら最安で十分。
- 🚨 **採用可否の本丸(未確認)**: APIドキュメントに「Each API request can only be used for a single user」。本アプリは tide を `env_cache`(mesh×日付)にキャッシュして**全ユーザーに使い回す**ので、この条項と矛盾しないか(キャッシュ&再配布が許可されるか)を **WorldTides に確認してから**採用すること。
- 実装の差し替え点: `app/Services/GetEnvData.php` の `calculateTideAction($tides,...)` の入力(WWOの `tide_data`/`tide_type`/`tideDateTime`)を WorldTides extremes(High/Low+時刻)に置換。上げ/下げ・満干・上げ3分/7分の%判定ロジックはそのまま流用可。

## 別件の進行状況(課金/TestFlight)
- IAP は実装済み(native expo-iap + `/api/iap/verify` + AppStoreService=App Store Server API)。
- 本番 .env に Open-Meteo customer URL+キー設定済み。`.p8`(SubscriptionKey_83CP7KNVBC.p8)を `storage/app/iap/` に配置、**chown www-data 済み**(Apacheワーカーが www-data のため)。`IAP_ENVIRONMENT=sandbox`(TestFlight検証用、本番は production)。
- 本番で `composer install` 済み(readdle/app-store-server-api 導入)。`php -r class_exists` が false だったのは **php -r がautoload読まない誤検知**。
- 本番DBは `migrate --force` 済み(operation_logs 等)。
- サブスクは ASC で「送信準備完了」、**初回はAppバージョン審査に紐づけて提出**が必要。Sandboxテスターは別途必須。

## 進捗更新(2026-06-12 このセッション)
ユーザー指示で方針が「2段階」から「**WWO 完全廃止の一括移行**」に変わり、実装まで完了した。

- backend 新ブランチ **`feature/env-data-openmeteo-worldtides`**(最新 main `e645697` 起点)にコミット済み: **`3814b9b`**。
  - `fix/tide-data-error` に置いてあった未コミット15件はこのブランチへ引き継いだ(`fix/tide-data-error` は空のまま残骸。削除可)。
  - 内容: Open-Meteo(天気/風/気温/波/水温・既存移植のまま)+ **WorldTides extremes で tid_action を再実装**(`app/Services/WorldTidesClient.php` + `config/worldtides.php`)。バケット判定ロジック(上げ3分/7分等)と出力は不変。**WWO は完全削除**(config・ハードコードキー・サンプルJSON含む)。潮失敗は nullable 続行(500再発防止)。
  - phpunit **204 tests 緑**(コンテナで composer install 済み・GD エラーも解消)。Pint PASS。
- WorldTides 実装詳細: extremes を JST 日付でグルーピング。forecast=今日起点7日(1クレジット)、過去=前日起点3日(日界ズレ対策)。`dt`(unix UTC)→ Asia/Tokyo 変換。key 未設定/エラー時は warning ログ + 空配列。
- テスト: phpunit.xml に `WORLDTIDES_API_URL/KEY` を force 固定(.env 漏れ防止)。失敗時堅牢性テスト追加。

## 進捗更新2(2026-06-12 同日・「不明」バグ修正)
潮の動きが「不明」と出る件をユーザーの実キーで調査し、**`0bdfa25`** で修正済み:
1. **extremes フラグが送信されていなかった**(Guzzle が URL 直書きクエリを query 配列で上書き → 常に空応答)。query 配列に `'extremes' => ''` で修正。実キーで extremes 取得を確認済み → `findings/2026-06-12-guzzle-query-overwrite-flag-params.md`
2. **下げ3分/下げ7分の判定が WWO 時代から逆**だった。仕様(満潮→下げ3分(10-50%)→下げ7分(50-90%)→干潮、上げも対称)に統一。6種の時系列テスト追加。
3. 潮 null のキャッシュ行は TTL 間隔で再取得する**自己修復**を追加(障害期間の行が永久に「不明」のまま残らない)。
phpunit 205件緑。ユーザーの WorldTides キーは取得済み(.env の `WORLDTIDES_API_KEY` に設定する。コードには含めていない)。

## 次の一手(順番)
1. **WorldTides の契約確認(ユーザー)**: 「Each API request = single user」条項がキャッシュ&全ユーザー配信と矛盾しないか確認 → OK ならキー取得し本番 .env に `WORLDTIDES_API_KEY` を設定。
2. push(ユーザー)→ PR(緊急なので main 直 PR か develop 経由かはユーザー判断)→ デプロイ。デプロイ前に本番 .env へキー設定必須(未設定だと潮だけ null で動く=500にはならない)。
3. 品質実値照合: 気象庁潮位表(東京/大阪/那覇)と WorldTides extremes の時刻を突き合わせ。
4. WWO 返金/復旧の返信対応(復旧しても戻さない。返金交渉のみ)。
5. マージ後: workspace `CLAUDE.md` の env data 用語(「天気/波/水温/風/潮位=WWO」)と既知リスク#4/4b を更新。

## ユーザーの運用ルール(厳守)
- **push はユーザーがやる**(AIはローカルcommitまで)。**有料契約もユーザー**。
- backend hotfix は **main 起点**(今回の明示指示。通常規約は develop 起点)。
- テストは sqlite(`tests/bootstrap.php`)。`migrate:fresh/reset/db:wipe` 禁止。
- APIキーは config 既定値に書かず .env/Secrets。

関連: [[ai-advisor-onsite-stages]] / `findings/2026-05-29-env-data-wwo-only-no-terrain.md` / ADR-0007。
