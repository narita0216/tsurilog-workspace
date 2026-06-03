# 現地戦略(on-site)の大容量動画 — Gemini File API 対応と検証

- **Date:** 2026-06-03
- **関連:** ADR-0006、initiatives/ai-strategy-feature.md、`tools/onsite-video-poc.sh`
- **対象:** backend `feature/ai-strategy`(`GeminiClient` / `CreateOnSiteStrategyController` / `local_docker/Dockerfile`)

現地戦略の動画解析を「大容量動画(数十MB)でも壊れない」ようにし、実 Gemini で検証した記録。

## 実装

- **Gemini File API 経路を追加**(`GeminiClient::analyzeVideo` が生バイトを受け取り、サイズで自動分岐):
  - `<= gemini.inline_max_bytes`(既定 7MB): `inline_data`(base64)で 1 リクエスト。
  - 超過: **resumable upload(`/upload/v1beta/files`)→ ACTIVE までポーリング → `file_data.file_uri` で `generateContent`**。
  - inline は総リクエスト ~20MB 上限があるため、30秒動画(数十MB)は File API が必須。
- controller は base64 化をやめ**生バイトを渡す**(GeminiClient がサイズ判定)。
- config: `gemini.inline_max_bytes` / `file_poll_attempts` / `file_poll_interval` を追加。

## ★ ハマりどころ(実検証で判明)

1. **PHP のアップロード上限がデフォルトで弾く。** `post_max_size=8M` / `upload_max_filesize=2M` のため、
   14MB の動画は**Laravel に届く前に PHP が拒否**(`POST Content-Length ... exceeds the limit of 8388608 bytes`)。
   - 対処: `local_docker/Dockerfile` に ini を追加(`post_max_size=120M` / `upload_max_filesize=100M` / `memory_limit=512M`)。
   - **本番でも同等設定が必須**(php.ini + nginx/ALB の `client_max_body_size`)。OnSiteStrategyRequest の動画上限(~100MB)と整合させること。
   - メモリ: `$file->get()` で動画全体をメモリに読むため `memory_limit` も引き上げ(100MB 動画 → 512M 設定)。
2. **ローカル phpunit が dev DB を消す。** テストが同一 Postgres + RefreshDatabase のため、`phpunit` 実行で
   dev データ(手動作成した `qa_tester` 等)が**全消去**される。QA 前にユーザ/データを作り直す必要がある。
   - 将来: テスト用 DB を分離するか、QA データ投入を seeder 化すると安全。
3. **`composer install --no-dev`(本番 CMD)で phpunit が消える。** docker イメージ再ビルド後にテストするには
   `composer install`(dev 込み)を流し直す。

## 検証結果(実 Gemini, 2026-06-03)

- 14MB 合成動画(ffmpeg `testsrc2` 1080p/15s)を on-site エンドポイントへ multipart 送信 → **HTTP 200 / 35s**。
- **File API 経路を通過**(>7MB)。Gemini が動画を解析し `video_summary` を返し、Claude が現地戦略を生成、利用制限(`remaining_count`)も動作。
- **プロンプト品質の確認**: Gemini は合成動画を正しく「カラーバーテストパターンで、海の透明度・濁り・海面(波立ち/うねり/風)・周辺地形(磯/堤防/河口/サーフ/テトラ)は読み取れない」と回答。
  → VIDEO_PROMPT が**狙い通り釣りに有用な特徴を抽出対象にしている**ことが確認できた(実海動画なら同特徴を抽出する)。
- **実海動画での品質評価は本物の海映像が必要**。`tools/onsite-video-poc.sh <video>` に実映像を渡せば同手順で検証可能(`FORCE_FILE_API=1` で小動画でも File API を強制)。
- native からの実機アップロードは **iOS Simulator にカメラが無い**ため実機が必要(backend パイプライン品質は上記 PoC で担保)。

## テスト/本番サーバでの不具合と修正(2026-06-03 追記)

テスト環境(dev.api、`php:8.4-apache` の Docker)で現地戦略が失敗 → ユーザートークンで curl 切り分け:
- **pre-trip(動画なし)= 200 正常**(キー・Claude・DB・マイグレーションOK)
- **on-site(動画あり)= `422 {"message":"validation.uploaded"}`** ← **3.6MB の動画でも失敗**

原因: **本番 `Dockerfile`(php:8.4-apache)に php.ini 上限設定が無く、既定の `upload_max_filesize=2M`/`post_max_size=8M`** のまま。動画が PHP 層で破棄され Laravel の `uploaded` 検証が落ちていた。`local_docker/Dockerfile` だけ直していて**本番 Dockerfile を直し忘れていた**(両方必要)。

修正:
- **本番 `Dockerfile` に conf.d** を追加(`upload_max_filesize=100M`/`post_max_size=120M`/`max_execution_time=180`)。VPS で pull → コンテナ再起動で反映。
  - `max_execution_time`: Apache mod_php 既定30s では on-site(File API+Gemini+Claude で ~40s)が**タイムアウトする**ため引き上げ。
  - `memory_limit` は据え置き、**on-site endpoint だけ `ini_set` で 512M**(全体に影響させない方針)。
  - ※ `upload_max_filesize`/`post_max_size` は **`PHP_INI_PERDIR` で `ini_set` 不可**。コンテナ php.ini か Apache `<Location>`/FPMプールでしか変えられない。
- **サイズ超過の親切なエラー**: `OnSiteStrategyRequest::messages()` で `video.max`/`uploaded`/`mimetypes` に日本語文言。native は `apiClient` に `Accept: application/json` を明示(無いと検証失敗が **302 リダイレクト**になり JSON が返らない)+ `getApiErrorMessage` が 422 の `errors[field][0]` を本番でも表示。
- 実海動画(3.6MB)での品質も別途確認済み: Gemini が「岩壁に囲まれた穏やかな入り江・透明度非常に高い・岩磯場」と正確に解析し、Claude が動画+環境データを融合した現地戦略を生成。
