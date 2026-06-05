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
- `routes/admin.php` を **web グループ無し(ステートレス)** で登録し `admin.ip` で保護(IP許可リスト `ADMIN_ALLOWED_IPS` + 任意 Basic 認証 `ADMIN_BASIC_USER/PASS`)。未設定時は local のみ許可。
  - ※ web グループを外したのは、管理画面が session/cookie/CSRF 不要で、`EncryptCookies` の APP_KEY 依存を避けるため(テストの `MissingAppKeyException` 回避にもなった)。
- `/admin` ダッシュボード: 日別DAU(操作ログ)・API別利用・**リピート率(操作ログ2日以上/1日以上)**・アンケート分布を **Chart.js(CDN)** で可視化。KPIカード(総ユーザー/回答数/活動ユーザー/リピート率/記録作成ユーザー)。
- `/admin/users`: 活動日数・最終活動・釣行記録数・アンケート回答の一覧(Postgres は PK group by で users.* 集計可)。

## テスト・確認
- backend テスト追加: 操作ログ(1日1回/非認証は記録なし)、アンケート(保存/422)、管理画面(許可IP=200・不許可=403)。**全187 green**。
- テストは sqlite :memory:(`phpunit.xml`)。**dev の Postgres は触らない**(qa_tester 再作成不要)。phpunit.xml にテスト用 APP_KEY を追加。

## デプロイ時の手作業
- backend pull(`feature/admin-analytics`)→ `composer install` 不要(新規依存なし)→ `php artisan migrate`(operation_logs / users survey 列)。
- **`.env` に `ADMIN_ALLOWED_IPS`(運営者の固定IP・カンマ区切り)を設定**(未設定だと本番は全403)。必要なら `ADMIN_BASIC_USER/PASS` も。
- 管理画面 URL: `https://<backend>/admin`。
- native は `feature/onboarding-survey` を pull。

## 戦略メモ
- これで「リピート率(操作ログ2日以上)」「流入チャネル(Q1)」「釣行予定/頻度(Q2/Q3)」が管理画面で見える。
- 判断軸: リピート率が低い & 釣行頻度も低い → 集客より「行かない時も開く理由(機能)」が課題。リピート率は出てるが母数不足 → Q1で効くチャネルに集客投資。
