# 運営者管理画面 + API操作ログ + 初回アンケート(リピート率分析基盤)

- 日付: 2026-06-05
- ブランチ: **develop 起点の新ブランチ**(AI戦略系 feature/ai-strategy とは独立)
  - backend: `feature/admin-analytics`(reomin・**ローカルコミット**、push は owner)
  - native: `feature/onboarding-survey`(narita0216・**push 済み**)
- 関連: 既存「釣果率」分析(GetAnalysisRateController)、ADR-0006

## 目的(事業戦略)
釣行記録が数件(集客1ヶ月)で、作られない理由が「アプリの問題」か「釣行頻度の問題」か不明。
**リピート率**を測り、①集客にお金をかける ②機能改善する、の方針判断に使う。確実なリピートと機能性が確認できたらインフルエンサー等で本格集客。

## 実装した3機能

### 1. API操作ログ(1ユーザー×1API×1日)
- `operation_logs`(user_id, action=ルートURI, log_date, unique)。`LogOperation` ミドルウェアを**認証APIグループ全体**に付与し `insertOrIgnore` で1日1回記録。
- 「釣りに行かない時もアプリを開いているか」「どの画面/機能が使われているか」を Firebase より明確に把握。

### 2. 初回アンケート(未回答ゲート)
- `users` に `survey_source / survey_visit_plan / survey_frequency / survey_answered_at`。null があれば native でログイン後に**回答必須ゲート**(`app/survey.tsx`、LoggedInLayout で `survey_completed=false`→`/survey` replace)。既存ユーザーもリリース後の初回起動で回収。
- `POST /api/survey`、`/users/my` に `survey_completed`。選択肢は `config/survey.php`(値=>ラベル)で API/管理画面共有。
- Q1 流入経路(YouTube/TikTok/IG/X/Web/AppStore/友人/その他)、Q2 釣行予定(今週末/1ヶ月内/予定なし)、Q3 頻度(週1+/月2/月1/数ヶ月/半年/年1/行かない)。

### 3. 運営者管理画面(Blade)
- **当初 IP 制限で実装 → ユーザー要望でログイン方式に変更(2026-06-05)。** メール+パスワード(`.env` の `ADMIN_EMAIL`/`ADMIN_PASSWORD`)のセッションログイン。`AdminAuth` ミドルウェアで `/admin` を保護、未ログインは `/admin/login` へ。パスワード未設定ならログイン不可(安全側)。
  - 管理画面は **web グループ(session/cookie)** で `routes/web.php` に登録。→ `EncryptCookies` が **APP_KEY 必須**(後述の落とし穴)。
  - 削除: `RestrictAdminIp` ミドルウェア / `routes/admin.php` / `ADMIN_ALLOWED_IPS`/`ADMIN_BASIC_*`。
- `/admin` ダッシュボード: 日別DAU(操作ログ)・API別利用・**リピート率(操作ログ2日以上/1日以上)**・アンケート分布を **Chart.js(CDN)** で可視化。KPIカード(総ユーザー/回答数/活動ユーザー/リピート率/記録作成ユーザー)。
- `/admin/users`: 活動日数・最終活動・釣行記録数・アンケート回答の一覧(Postgres は PK group by で users.* 集計可)。

## テスト・確認
- backend テスト: 操作ログ(1日1回/非認証は記録なし)、アンケート(保存/422)、管理画面(未ログイン→/login・ログイン成功→ダッシュボード・ログアウト・誤資格情報)。**全191 green**(sqlite)。
- 管理画面の runtime も確認: `/admin`→302→`/admin/login`、`/admin/login`→200。

## ⚠️ 落とし穴: テストが開発用 Postgres を破壊していた(重大)
- **症状**: `docker-compose-local.yml` は `env_file: .env` でコンテナのプロセス環境に `APP_ENV=local` / `DB_CONNECTION=pgsql` / (起動時点の)`APP_KEY` を焼き付ける。Laravel の `env()` は **`$_SERVER`(ServerConstAdapter)を `$_ENV` より優先**して読むため、`phpunit.xml` の `<env>`(sqlite/testing)が**握りつぶされ**、`RefreshDatabase` が**開発用 Postgres `tsurilog` に `migrate:fresh`**(全テーブル DROP)を実行していた。前セッションの「sqlite で実行・dev pg は触らない」という認識は**誤り**で、ローカルでは pg が毎回ワイプされていた(`users/records/logs=0` の原因)。
- **空 APP_KEY も同様**に `$_SERVER` 経由で焼き付き、web グループの `EncryptCookies` が `MissingAppKeyException`(前セッションが admin をステートレス化した真因)。
- **対策**: `tests/bootstrap.php` を新設し、env リポジトリ構築前に `$_SERVER/$_ENV/putenv` を強制上書き(`APP_ENV=testing`/`DB_CONNECTION=sqlite`/`:memory:`/有効な `APP_KEY`)。`phpunit.xml` の `bootstrap` をこれに変更。→ テストは必ず sqlite :memory:。**CI は env_file 汚染が無いので元から sqlite で無害**。
- **ローカル docker の APP_KEY**: コンテナ起動時に `.env` を焼き付けるため、`.env` の `APP_KEY` が空のままだと **/admin が runtime で 500**。`php artisan key:generate` 後に **`docker compose -f docker-compose-local.yml up -d --force-recreate api`** で反映が必要(`docker restart` では env_file 再読込されない)。**注意: 同コンテナの entrypoint は `composer install --no-dev` を走らせ phpunit を消す → recreate 後は `composer install` で dev 依存を戻す**。

## デプロイ時の手作業
- backend pull(`feature/admin-analytics`)→ `composer install` 不要(新規依存なし)→ `php artisan migrate`(operation_logs / users survey 列)。
- **`.env` に `ADMIN_EMAIL` と `ADMIN_PASSWORD` を設定**(パスワード未設定だとログイン不可)。**`APP_KEY` 必須**(管理画面のセッション暗号化)。
- 管理画面 URL: `https://<backend>/admin`(→ `/admin/login`)。
- native は `feature/onboarding-survey` を pull。

## 戦略メモ
- これで「リピート率(操作ログ2日以上)」「流入チャネル(Q1)」「釣行予定/頻度(Q2/Q3)」が管理画面で見える。
- 判断軸: リピート率が低い & 釣行頻度も低い → 集客より「行かない時も開く理由(機能)」が課題。リピート率は出てるが母数不足 → Q1で効くチャネルに集客投資。
