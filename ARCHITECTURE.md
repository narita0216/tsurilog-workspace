# 釣りログ Architecture(横断アーキテクチャ)

`tsurilog-native`(アプリ)と `tsurilog-backend`(API)を中心とした、釣りログサービス基盤の横断アーキテクチャドキュメントです。

> **釣りログの事業:** 釣行記録と環境データ分析で「データに基づく釣り」を支援するスマホアプリ(iOS / Android、主要機能無料)。物販・決済は存在しない。

---

## 1. 全体構成

```
┌─────────────────────────────────────────────────────────────┐
│                     エンドユーザー(釣り人)                    │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
            ┌───────────────────────────────┐
            │      tsurilog-native           │
            │   React Native / Expo SDK 54   │
            │   iOS / Android (dev client)   │
            │                                 │
            │   axios apiClient               │
            │   Authorization: Bearer <token> │
            └───────────────┬─────────────────┘
                            │  HTTPS  (唯一の結合面 = API コントラクト)
                            │  /api/*
                            ▼
            ┌───────────────────────────────┐
            │      tsurilog-backend          │
            │   Laravel 12 / PHP 8.4         │
            │                                 │
            │  ┌───────┐ ┌───────┐ ┌────────┐│
            │  │  api  │ │ queue │ │scheduler││   ← docker compose services
            │  └───┬───┘ └───┬───┘ └───┬────┘│
            └──────┼─────────┼─────────┼──────┘
                  │         │         │
       ┌──────────▼───┐ ┌───▼─────┐ ┌─▼─────────────┐
       │ PostgreSQL16 │ │ push 配信 │ │ 定期バッチ      │
       │   (db)       │ │(FCM/APNs)│ │ 潮汐取得 02:00  │
       └──────────────┘ └──────────┘ │ 自動終了 毎時    │
                                     └────────────────┘
                  │
       外部サービス(アプリ/API から):
       - Firebase(Analytics / push 基盤)
       - Apple Sign In / Google Sign In(ID トークン検証)
       - Google Mobile Ads(AdMob)
       - 気象/海象 API(env data: 潮・潮位・気温・水温・風・波)
```

**airtrunk との最大の違い:** airtrunk は「2 アプリが同一 DB を直接読み書き」する構成だったため横断の核心が *共有テーブル/重複モデル* だった。釣りログは **アプリ → REST API → DB の一方向**で、DB に触れるのは backend だけ。したがって横断の核心は **API コントラクト(エンドポイント・型・レスポンス形)の整合性**である。

---

## 2. コンポーネント境界

### 2.1 tsurilog-native(アプリ)

**責務(ユーザー接点):**
- マップ表示・GPS 現在地追跡・地点ピン(長押しで設置)
- 釣行の開始/終了(`is_fishing` モード)・離脱検知による自動終了通知
- 釣果入力(釣行中の「釣れた！」+ 音声認識による魚種登録、後からの手入力編集)
- 自分の釣行記録の一覧/詳細/編集、公開・非公開切替
- ピン周辺(半径 1km)の他者公開記録の一覧/詳細、分析(釣れやすさ・魚種/釣法傾向・混雑)
- プロフィール表示/編集(アイコン・ニックネーム・得意釣法・ターゲット魚種・タックル)
- 通知一覧/既読、設定(通知 ON/OFF・自動公開 ON/OFF)
- ログイン(Apple / Google)

**構造:**
- 画面: `app/`(expo-router file-based、`(tabs)/` にマップ・自分の記録・通知・設定・プロフィール)
- API クライアント: `api/<domain>/<action>.ts`(1 リクエスト 1 ファイル + 型)
- サーバ状態: `hooks/use-*.ts`(TanStack Query)
- 画面共通 UI: `components/`、グローバル状態: `stores/app-store.ts`(zustand、主にトークン)
- 入力検証: `validation/`(zod)

### 2.2 tsurilog-backend(API)

**責務:**
- 認証(Apple/Google ID トークン検証 → `api_token` 発行)
- 釣行記録・釣果ログ・ピンの CRUD と公開制御
- マスタ提供(魚種・釣法 ほか)
- 分析集計(env_data / condition_stats / rate)
- プッシュ通知の生成・キューイング・配信(`queue`)
- 定期バッチ(潮汐取得・釣行自動終了)(`scheduler`)

**構造(README の設計思想):**
- `app/Http/Controllers/Api/<Verb><Noun>Controller.php` — **1 エンドポイント 1 コントローラ / public は `index` のみ**
- `app/Http/Requests/` — バリデーション
- `app/Services/` — **複数コントローラで共有する処理のみ**(`RecordResponseService` / `UserResponseService` / `GetEnvData` / `CalcMesh*Service` / `PushNotificationService` / `NotificationService` など)
- `app/Models/` — Eloquent(`Record` / `Log` / `Pin` / `User` / `*Master` / `*Cache` / `Notification` / `PushDevice` / `Setting` …)
- `database/migrations/` — スキーマ + マスタ投入(追記式)
- `routes/api.php` — 全ルート定義 / `routes/console.php` — スケジュール定義

---

## 3. API コントラクト(結合面の詳細)

### 3.1 真実の所在

| 関心事 | 真実の所在 |
|---|---|
| どのエンドポイントが存在するか | `tsurilog-backend/routes/api.php` |
| リクエスト/レスポンスの形(実装) | backend の Request クラス + `*ResponseService` / `*FormatterService` |
| アプリが期待する形 | `tsurilog-native/api/**/*.ts` の `*ApiRequestParamsType` / `*ApiResponseType` |
| 対外仕様 | `tsurilog-backend/openapi.yml`(**現状ズレあり** → findings 参照) |

### 3.2 エンドポイント一覧(2026-05-28 時点、routes/api.php 基準で 35 本)

| グループ | 主なエンドポイント | 認証 |
|---|---|---|
| 認証 | `POST /auth/apple`、`POST /auth/google` | 不要 |
| ユーザー | `GET/PUT/DELETE /users/my`、`GET /users/{id}` | 必要 |
| 釣行記録 | `GET /records`、`/records/my`、`/records/my/{id}`、`POST /records/start`、`GET /records/is_fishing`、`POST /records/end`、`POST /records/{id}/public|private`、`DELETE /records/{id}`、`GET /records/{id}` | 必要 |
| 釣果ログ | `POST /logs`、`PUT /logs/{id}`、`DELETE /logs/{id}` | 必要 |
| ピン | `GET /pins`、`POST /pins`、`DELETE /pins/{id}` | 必要 |
| 分析 | `GET /analysis/env_data`、`/analysis/condition_stats`、`/analysis/rate` | 必要 |
| マスタ | `GET /fish_master`、`/fishing_style_master` | 必要 |
| 通知 | `GET /notifications`、`POST /notifications/read` | 必要 |
| Push 端末 | `POST /push-devices/register|unregister` | 必要 |
| 設定 | `GET /settings`、`POST /settings/toggle-notification|toggle-auto-public` | 必要 |
| ダッシュボード | `GET /dashboard` | 必要 |

> native は全パスに `/api` プレフィックスを付与(`/api/logs` 等)。Laravel routes 側は `/api` を自動付与するため定義には書かない。

### 3.3 共通レスポンス慣習
- 多くのレスポンスが `is_success` / `error_message` を含む独自形。
- 認証失敗 = HTTP 401 + `{is_success:false, error_message, user:{}}`。
- native の axios interceptor が **401 でトークン破棄 → /login 遷移**。新規エンドポイントもこの形に合わせる。

---

## 4. データモデル(backend のみが所有)

主要テーブル(`database/migrations/`):

| テーブル | 役割 |
|---|---|
| `users` / `user_providers` | ユーザーと OAuth プロバイダ紐付け。`api_token` を保持 |
| `records` | 釣行記録(セッション)。位置・期間・環境スナップショット |
| `logs` / `log_images` | 釣果ログと画像 |
| `pins` | 保存地点 |
| `settings` | 通知 ON/OFF・自動公開 ON/OFF |
| `notifications` / `notification_reads` / `notification_dispatch_logs` | 通知本体・既読・配信ログ |
| `push_devices` | プッシュ端末トークン |
| `env_cache` | 環境データキャッシュ(mesh 5km 単位でユニーク) |
| `score_cache` / `best_pattern_cache` | 分析結果のキャッシュ |
| `*_master`(fish / fishing_style / weather / wind_speed / wave_height / tid_type / tid_action) | マスタ |
| `action_logs` | 行動ログ |

> 注: `tid`(潮汐)関連は `tid_type` / `tid_types` / `tid_type_master` / `tid_action_master` が混在。マイグレーション履歴から実体を確認すること。

---

## 5. デプロイ・実行構成

### 5.1 backend
- **ローカル/本番とも Docker Compose**。サービス: `api`(HTTP)/ `queue`(`queue:work`、push 配信)/ `scheduler`(`schedule:work`、定期バッチ)/ `db`(Postgres16)。
- 本番は **既存 Apache が `/api` を `127.0.0.1:8080` の Laravel コンテナへ ProxyPass**(`DEPLOYMENT.md`)。8080 は外部遮断(ufw)。
- CI: `.github/workflows/tests.yml` が PR to `main` で Postgres16 + PHP8.4 でマイグレーション + `php artisan test`。

### 5.2 native
- **EAS** で development / preview / production をビルド(`eas.json`)。本番は App Store / Google Play へ。
- 環境変数: ローカルは `.env`(`EXPO_PUBLIC_API_DOMAIN` / Google client id)、ビルドは EAS Secrets。
- Firebase 設定: `GoogleService-Info.plist`(本番)/ `-dev.plist`(開発)。AdMob app id は `app.json`。

---

## 6. 認証・セッション

- アプリは **Apple / Google のネイティブ認証**で ID トークンを取得 → backend が検証 → `users.api_token`(UUID)を返す。
- 以降は **`Authorization: Bearer <api_token>`** を全 API に付与。`auth.apitoken` ミドルウェアが `users.api_token` でユーザー解決し `authenticated_user` を request に注入。
- backend 自体のセッション(`SESSION_DRIVER=database`)は API トークン認証とは別(主に web / queue 用)。
- **トークン rotation / 失効の仕組みは薄い**(漏洩時リスク)。取り扱いは `auth.apitoken` 経由に統一。

---

## 7. CI/CD・テスト

| 項目 | backend | native |
|---|---|---|
| 静的解析 | Laravel Pint | ESLint(`eslint.config.js`) |
| 型チェック | (PHP)`php -l` / Pint | `tsc --noEmit`(`npm run lint` に内包) |
| 整形 | Pint | Prettier |
| 単体/機能テスト | PHPUnit(`tests/Feature` `tests/Unit`) | 実質なし(課題) |
| CI | GitHub Actions(PR to main) | なし(EAS ビルドのみ) |
| 横断コントラクト検査 | — | `harness-engineering/tools/contract-check.sh`(本ハーネスで追加) |

---

## 8. 既知の構造的負債(優先度順)

1. **API コントラクトの 3 点ドリフト**(routes / native / openapi)。最優先。`contract-check` で常時監視。
2. **openapi.yml の陳腐化**(analysis 系の名称ズレ + 13 ルート未記載)。
3. **テストの薄さ**(特に native、backend も critical path 不足)。
4. **環境データの外部 API 依存**(潮汐・気象)。キャッシュ(env_cache / mesh)前提を壊さない。
5. **認証トークンの失効/rotation 機構の薄さ。**
6. **潮汐関連テーブルの命名揺れ**(`tid_type` 系の重複)。
7. **ワークスペース親が git 管理外**(ハーネス資産のバージョン管理は要 `git init`)。

---

## 9. 整備したい横断ダイアグラム(TODO)

- [ ] エンドポイント別の native ↔ backend ↔ openapi 対応マトリクス(コントラクトカタログ)
- [ ] 釣行のライフサイクル(start → 釣果ログ → end / 自動終了)とテーブル状態遷移
- [ ] 分析パイプライン(env data 取得 → mesh キャッシュ → score / best_pattern)
- [ ] 通知の経路(生成 → queue → push_devices → 配信ログ)

---

## 10. 参考
- AI への指示 → `CLAUDE.md` Section 8
- セットアップ → `README.md`
- ハーネス工学 → `harness-engineering/README.md`
