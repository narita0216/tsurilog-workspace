# 釣りログ Workspace — AI Context

このファイルは `tsurilog-workspace/` を作業ディレクトリとして Claude Code を起動した AI エージェント向けの**横断コンテキスト**です。各サブリポジトリにはリポジトリ固有の `CLAUDE.md` が別途存在する場合があります。

---

## 1. このワークスペースは何か

「釣りログ」(https://tsuri-log.com/)は、**釣行の記録と環境データ分析でデータに基づく釣りを支援するスマホアプリ**(iOS / Android、主要機能無料)です。「感覚ではなくデータで、次の一匹を狙いやすく」をコンセプトに、位置情報ベースの釣果記録と、月・時間・潮・潮位・気温・水温・風速・波高といった環境条件の分析を提供します。

このワークスペースは、釣りログを構成する **2 つのリポジトリを横断的に扱うための作業ディレクトリ**です。サブリポジトリは個別に clone して兄弟配置します。

**配置:**

```
tsurilog-workspace/
├── CLAUDE.md                 ← 横断 AI コンテキスト(本ファイル)
├── ARCHITECTURE.md           ← 横断アーキテクチャ
├── README.md                 ← オンボーディング手順
├── .gitignore                ← サブリポジトリ・秘密を除外
├── .mcp.json                 ← GitHub MCP 設定
├── .claude/                  ← チーム共有ハーネス設定(commands / agents / settings)
├── harness-engineering/      ← ハーネス分析・ADR・ツール・findings
├── tsurilog-native/          ← アプリ(別リポジトリ / gitignore 対象)
└── tsurilog-backend/         ← API(別リポジトリ / gitignore 対象)
```

> **重要:** ワークスペース親ディレクトリ自体が git リポジトリ(**メタリポジトリ**)で、ハーネス資産(本ファイル群)を版管理する。
> - remote: `git@github-narita0216:narita0216/tsurilog-workspace.git`(owner: narita0216)
> - ブランチ: **`master`**(workspace の唯一の作業ブランチ。`develop` は使わない)
> - サブリポ(`tsurilog-native` / `tsurilog-backend`)は `.gitignore` で除外され、それぞれ独立した git リポジトリ。
> このメタリポは本番デプロイを持たない(ハーネス/ドキュメント/ADR 用)ため、コードリポとは運用ルールが異なる(§6.1)。

---

## 2. リポジトリの役割

| リポジトリ | 役割 | git remote |
|---|---|---|
| `tsurilog-native` | **アプリ本体**(React Native / Expo)。ユーザーが触る全画面・GPS・マップ・釣行記録・分析表示・通知 | `git@github-narita0216:narita0216/tsurilog-native.git` |
| `tsurilog-backend` | **API サーバー**(Laravel)。認証・釣行/釣果データ・マスタ・分析集計・プッシュ通知配信・潮汐取得バッチ | `https://github.com/reomin/tsurilog-backend.git` |
| `tsurilog-workspace` | **メタリポ(本ディレクトリ)。** 横断ハーネス・ドキュメント・ADR・findings。コードは含まない | `git@github-narita0216:narita0216/tsurilog-workspace.git`(branch: `master`) |

**両コードリポは DB を共有しない。** airtrunk のような「同一 DB を複数アプリが直接読み書き」する構成ではなく、**アプリ → REST API → DB という一方向**。したがって横断作業の核心は「共有テーブル」ではなく **API コントラクト(エンドポイント定義)の整合性**(Section 4)。

### ドメイン用語

| 用語 | 意味 |
|---|---|
| `record`(釣行記録) | 1 回の釣行セッション。開始(start)〜終了(end)で 1 件。位置・期間・環境データを持つ |
| `log`(釣果ログ) | 釣行記録内の個々の「釣れた」記録。魚種・サイズ・匹数・画像・時刻 |
| `pin`(ピン) | ユーザーが保存した地点(緯度経度)。半径圏内の記録/分析の起点 |
| `is_fishing`(釣行中) | ユーザーが現在釣行中かのフラグ。釣行開始でオン、終了/自動終了でオフ |
| `master`(マスタ) | 魚種(fish)・釣法(fishing_style)・天気・風速・波高・潮汐種別などの定義データ |
| `env data`(環境データ) | 釣行地点・時刻の気象/海象(潮・潮位・気温・水温・風・波)。**天気/波/水温/風/潮位 = WWO**(backend `app/Services/GetEnvData.php` → `EnvCache`、mesh 5km×date×hour)、**潮回り(tid_type)= tide736.net**(`FetchTidTypeService`)。値は**マスタID にバケット化**して保存(生値でない)。forecast を再取得せず長期キャッシュ=精度劣化要因。**地形/水深は未取得**。詳細 → `findings/2026-05-29-env-data-wwo-only-no-terrain.md` |
| `analysis`(分析) | ピン半径圏内の釣れやすさ・魚種/釣法傾向・混雑状況の集計 |
| `mesh`(メッシュ) | 環境データのキャッシュ単位(500m / 1km / 5km の地理メッシュ) |

「商品」「カート」「決済」は本サービスに存在しない(物販ではない)。

---

## 3. 技術スタック

### tsurilog-native(アプリ)

| カテゴリ | 内容 |
|---|---|
| 言語 | TypeScript |
| フレームワーク | React Native 0.81 / **Expo SDK 54**(New Architecture 有効) |
| 画面遷移 | expo-router(typed routes / file-based) |
| UI | gluestack-ui v3 + **NativeWind / Tailwind**(`global.css` / `tailwind.config.js`) |
| 状態/通信 | **TanStack Query**(サーバ状態・キャッシュ)+ axios(`api/api-client.ts`)+ zustand(アクセストークン程度) |
| フォーム | react-hook-form + **zod**(`validation/`) |
| 地図/グラフ | react-native-maps / victory-native / react-native-chart-kit |
| 認証 | expo-apple-authentication(Apple)/ expo-auth-session(Google) |
| その他 | Firebase Analytics、expo-notifications(push)、react-native-google-mobile-ads、expo-image-picker |
| 静的検査 | ESLint(`eslint.config.js`)+ `tsc --noEmit`、Prettier |
| ビルド/配布 | **EAS**(`eas.json`: development / preview / production) |

> Expo Go では動かない(カスタムネイティブコードあり)。**開発ビルド(dev client)**が必要。

### tsurilog-backend(API)

| カテゴリ | 内容 |
|---|---|
| 言語 | **PHP 8.4** |
| フレームワーク | **Laravel 12** |
| DB | **PostgreSQL 16**(注: airtrunk は MySQL。釣りログは Postgres) |
| 認証 | 自前の Bearer トークン(`users.api_token`)+ `auth.apitoken` ミドルウェア。Apple/Google の ID トークンを検証して発行 |
| 非同期 | `QUEUE_CONNECTION=database` + `queue` コンテナ(`queue:work`)= プッシュ通知配信 |
| 定期実行 | `scheduler` コンテナ(`schedule:work`)= 潮汐取得(02:00)・釣行自動終了(毎時) |
| ローカル | **Docker Compose**(`api` / `queue` / `scheduler` / `db`)。`docker-compose.yml`(本番相当)/ `docker-compose-local.yml`(ローカル) |
| 整形/検査 | **Laravel Pint**、PHPUnit |
| CI | GitHub Actions(`.github/workflows/tests.yml`)= PR to `main` で Postgres16 + PHP8.4 でテスト |
| 仕様書 | `openapi.yml`(OpenAPI 3.0) |

---

## 4. 横断作業の核心 — API コントラクト

両リポを繋ぐ唯一の面は **HTTP エンドポイント**。その定義が **3 箇所に分散**しており、レビューだけでは静かにズレる:

| # | 場所 | 役割 | 真実度 |
|---|---|---|---|
| 1 | `tsurilog-backend/routes/api.php` | Laravel のルート定義 | **実装の真実** |
| 2 | `tsurilog-native/api/**/*.ts` | アプリが叩くクライアント(axios) | アプリの期待 |
| 3 | `tsurilog-backend/openapi.yml` | 仕様書 | ドキュメント(現状ズレあり) |

**⚠️ 既知のドリフト(2026-05-28 計測):** `openapi.yml` の `/analysis/env-data` `/analysis/scores` `/analysis/best-pattern` は実ルート(`/analysis/env_data` `/analysis/condition_stats` `/analysis/rate`)と一致せず、さらに settings / notifications / push-devices など 13 ルートが未記載。詳細 → `harness-engineering/findings/2026-05-28-openapi-route-drift.md`。

### パスの対応規則

- **native は `/api` プレフィックス付き**(`apiClient.post("/api/logs")`)、**Laravel routes は無し**(`Route::post('/logs', ...)`)。`api.php` は自動的に `/api` 配下。
- パスパラメータ: native `${data.id}` ↔ routes `{id}`。
- **`contract-check.sh` がこの 3 点を機械突合**する(`/contract-check`)。API を触ったら必ず実行(Section 8)。

### レスポンスの共通形

backend のレスポンスは概ね `is_success` / `error_message` を含む独自フォーマット(Laravel 標準の例外 JSON ではない)。認証失敗は HTTP 401 + `{is_success:false, error_message, user:{}}`。native の axios interceptor は **401 で自動的にトークン破棄 → /login へ遷移**(`api/api-client.ts`)。新規エンドポイントもこの慣習に合わせる。

### 認証フロー

1. アプリが Apple/Google でサインイン → ID トークンを `POST /api/auth/{apple,google}` に送る
2. backend が検証し `users.api_token`(UUID)を発行して返す
3. 以降アプリは `Authorization: Bearer <api_token>` を全 API に付与(`auth.apitoken` ミドルウェア)
4. `auth/*` は **native では `apiClient` を経由しない**(トークン取得前のため別経路)。`contract-check` で「アプリ未使用」と出るが正常。

---

## 5. 横断分析・レビューの観点

AI で両リポを横断的に扱うとき、価値が出る分析角度:

### 5.1 API コントラクトのドリフト(最重要)
- routes / native / openapi の 3 点ズレ(`/contract-check`)。
- リクエスト/レスポンスの **型の食い違い**: native の `*ApiRequestParamsType` / `*ApiResponseType`(`api/**/*.ts`)と backend の Request バリデーション・レスポンス整形(`app/Http/Requests/` / `app/Services/*ResponseService.php`)。
- フィールド名の snake_case(API)↔ TS の型定義の整合。

### 5.2 マスタデータの整合
- 魚種・釣法・天気・風速・波高・潮汐種別は backend の seeder(`database/migrations/*_insert_*_master_data.php`)が真。native は `api/master/*` 経由で取得して表示。**ID をハードコードしない**(「その他」ID など)。

### 5.3 認証・権限境界
- 自分のデータ(`/records/my`)と他者の公開データ(`/records`)の境界。公開/非公開トグル(`/records/{id}/public|private`)。
- `auth.apitoken` が無いルートは認証なし(現状 `auth/*` のみ)。新規ルートを認証グループ外に置く時は明確な理由を。

### 5.4 非同期・定期処理
- プッシュ通知は `queue` コンテナ経由(同期送信 `--sync` は手動デバッグ専用)。
- 釣行自動終了(`app:auto-end-fishing-records`、毎時)・潮汐取得(`app:fetch-tid-type`、02:00)は `scheduler` 前提。ローカルで挙動確認する時は該当コンテナの稼働を確認。

---

## 6. ワークフロー

### 6.0 タスク管理

タスクは各コードリポの GitHub Issue / PR で管理する。横断的な調査ログ・意思決定・発見は `harness-engineering/` に蓄積する(下表)。

| 種類 | 置き場所 |
|---|---|
| 「やること」「バグ」「TODO」 | 各リポの GitHub Issue |
| 「なぜそう決めたか」(ADR) | `harness-engineering/decisions/` |
| 「現状どうなっているか」(調査) | `harness-engineering/assessment/` |
| 「進行中の取り組み」 | `harness-engineering/initiatives/` |
| 「気づき・落とし穴」 | `harness-engineering/findings/`(`YYYY-MM-DD-<topic>.md`) |

### 6.1 ブランチ戦略(両コードリポ共通)

| ブランチ | 役割 |
|---|---|
| `main` | **本番ブランチ。保護対象。** 直接 push 禁止。PR 経由のみ。backend は PR to main で CI(テスト)必須 |
| `develop` | **開発統合ブランチ。** 作業ブランチの起点・統合先 |
| `feature/*` | `develop` を起点に切り、PR で `develop` へ |

- **新規ブランチは必ず `develop` を起点**に切る。`main` を起点にしない。
- **`main` への直接 push / merge は行わない。**
- PR は人間レビューを受ける。AI が単独 merge しない。

**実装着手の手順(両コードリポ共通・必須):** コードリポ(native / backend)で機能実装を始めるときは、毎回この手順を踏む。

```bash
# 1. develop へ切替し、リモート最新を取り込む(必ず最新の develop 起点)
git checkout develop && git pull origin develop
# 2. develop を起点に作業ブランチを新規作成
git checkout -b feature/<topic>
# 3. 実装・コミット
# 4. push して develop への PR を作成(MCP 優先・§8.6)。base は必ず develop
```

- **両リポにまたがる機能は、native / backend それぞれで上記を行い、それぞれ `develop` への PR を立てる。** 対になる PR は本文で相互リンクする。
- 着手時に `main` に居たら(SessionStart の workspace-sync が警告する)、まず上記手順で `develop` 起点の作業ブランチへ移る。`main` 上で直接実装しない。

#### workspace メタリポ(`tsurilog-workspace` = 本ディレクトリ)

| ブランチ | 役割 |
|---|---|
| `master` | **唯一の作業ブランチ。AI が直接 commit / push 可。** `develop` は使わない |

- メタリポは本番デプロイを持たない(ハーネス/ドキュメント用)ため、コードリポと運用が異なる。
- **AI はハーネス整備(`CLAUDE.md` / ADR / `findings/` / `tools/` / `.claude/`)を `master` に直接 commit / push してよい。** feature ブランチ・PR・人間レビュー不要。
- **Stop フックで自動 commit & push される**(`harness-autosave.sh`、ADR-0005)。変更があれば毎ターン終了時に自動反映。手動で `git commit` / `git push` してもよい。
- ただし不可逆操作(`git push --force`、`git reset --hard`、履歴書き換え)は引き続き禁止。
- サブリポ(native/backend)の作業はそれぞれのリポ内で行い、上記コードリポのルールに従う。

### 6.2 横断調査を行うとき
1. `tsurilog-workspace/` で Claude Code を起動 → 本 `CLAUDE.md` が読まれる
2. 両リポにまたがる grep / コントラクト突合(`/contract-check`、`/endpoint-trace`)

### 6.3 単一リポの作業を行うとき
- 各リポに `cd` して通常通り。横断観点が要れば親に戻る。

---

## 7. 既知のリスク

| # | リスク | 影響 | 対応 |
|---|---|---|---|
| 1 | **API コントラクトのドリフト**(routes / native / openapi) | 404・型不一致・仕様書の信頼性低下 | `/contract-check` を API 変更時に必須化(ADR-0002) |
| 2 | openapi.yml が実装に追随していない | フロント/外部連携が古い仕様を参照 | コントラクトカタログ整備(initiative) |
| 3 | テスト: **backend は充実**(phpunit 181 tests・Feature/Unit、2026-05-29 実測 177 pass/4 error=GD拡張未導入のみ)、**native は実質なし** | native 側のリグレッション検知不能 | native の critical path にテスト追加(ROADMAP)。backend テストは `docker-compose-local.yml` で `./vendor/bin/phpunit`(`artisan test` 未定義)。env-data 移行は分析テストで担保 |
| 4 | 環境データ取得が **WWO 1 本依存**(品質疑問 + forecast 長期キャッシュで劣化) | 分析の精度低下 | **ADR-0007 で WWO 廃止を決定** → 天気/海象=Open-Meteo(JMAモデル・$29/月)、潮=tide736.net、地形=海しる。移行は段階的に・分析の Feature テスト必須。キャッシュは forecast 失効(TTL)を導入(潮は決定論的で対象外) |
| 4b | **WWO キーが backend `config/worldweatheronlineapi.php` の `env()` デフォルトにハードコード**(平文) | キー露出 | 新規 API キー(Claude/Gemini/海しる/波高)はデフォルト値に書かず `.env`/Secrets 注入。既存 WWO キーもローテーション検討 → `findings/2026-05-29-env-data-wwo-only-no-terrain.md` |
| 5 | 認証が自前 Bearer トークン(失効・rotation 機構が薄い) | トークン漏洩時の影響 | 取り扱いを `auth.apitoken` 経由に統一 |
| 6 | リポ所有者が分かれている(native: narita0216 / backend: reomin) | 権限・PR フローの分断 | MCP/PAT のスコープ確認(`.claude/README.md`) |

---

## 8. AI エージェントへの指示

### 8.0 動作検証はローカルで
- backend の動作確認は **Docker Compose**(`api`/`queue`/`scheduler`/`db`)で行う。本番 / 共有環境への直接接続で確認しない。
- native は **dev client + `npx expo start --dev-client`**(実機/シミュレータ)。UI を変えたら可能な範囲で実機確認し、できない場合はその旨を明示する。
- ローカル環境構築で判明した手順・ハマりどころは `harness-engineering/findings/` に都度記録。

### 8.1 API を触るときは `/contract-check` 必須(ADR-0002)
**`routes/api.php` / `tsurilog-native/api/**` / `openapi.yml` のいずれかを変更したら、必ず `/contract-check` を実行**し、3 点が整合していることを確認する。新規エンドポイントを足すときは **3 箇所すべて**(ルート定義・native クライアント・openapi)を同じ PR(または対になる PR)で更新する。`harness-engineering/tools/contract-check.sh`。

### 8.2 backend(Laravel)コード規約
README の設計思想を厳守する:
1. **1 エンドポイント = 1 コントローラ**。`app/Http/Controllers/Api/<Verb><Noun>Controller.php`。
2. **コントローラの public メソッドは `index` のみ**。ルーティングは `index` に集約。
3. **バリデーションは専用 Request クラス**(`app/Http/Requests/`)。Controller / Service に直書きしない。
4. **Service は複数コントローラで共有する処理だけ**。1 箇所でしか使わない処理は Controller の private メソッド。
5. **不要な Service を作らない**(Controller を薄くするためだけの Service は禁止)。
6. レスポンスは既存の `is_success` / `error_message` 慣習・`*ResponseService` に合わせる。
- 大きめの新規 PHP を書くときは `laravel-api-reviewer` サブエージェントにレビューを投げる。
- PHP 編集後は `php-lint.sh`(PostToolUse hook)で PHP 8.4 構文が自動チェックされる。PR 前に `/backend-check`(Pint `--test` + PHPUnit)を流す。

### 8.3 native(Expo / RN)コード規約
- 既存パターンに従う: `api/<domain>/<action>.ts` に 1 リクエスト 1 ファイル + `*ApiRequestParamsType` / `*ApiResponseType` の型定義。サーバ状態は **TanStack Query**(`hooks/use-*.ts`)、フォームは react-hook-form + zod(`validation/`)。
- スタイルは **`StyleSheet.create` + `constants/config` のダークテーマ**(`MAIN_COLOR` / `APPLICATION_BACKGROUND_COLOR` / `APPLICATION_TEXT_COLOR` 等)で書く。**実コードは 100% StyleSheet**(`className` 使用 0 件)で、新規もこれに合わせて一貫させる。NativeWind は導入済みだが未使用(経緯: `findings/2026-05-29-native-styling-nativewind-vs-stylesheet.md`)。
- 画面は **expo-router の file-based**(`app/`)。typed routes 前提。
- ハードコードした魚種/釣法 ID やマジックナンバーを避け、master API / 定数を参照。
- 変更後は `/native-check`(`expo lint` + `tsc --noEmit`)。整形は `npm run format`(Prettier)。
- 大きめの新規 TS/UI は `expo-rn-reviewer` サブエージェントにレビューを投げる。

### 8.4 危険操作
- `git push --force` / `git reset --hard` / 履歴書き換えは行わない(`.claude/settings.json` deny)。
- **`php artisan migrate:fresh` / `migrate:reset` / `db:wipe` はローカル DB を全消去**するため deny 済み。データを保ちたい時は通常の `migrate`。
- **`eas submit`(ストア提出)は AI が自走で行わない**(deny 済み)。`eas build` は明示指示があるときのみ。
- マイグレーションは追記式(`database/migrations/`)。既存マイグレーションを書き換えず新規ファイルを足す。

### 8.5 ハーネスの自律改善(workspace は AI 管理)
- 会話・実装で得た知見は **`CLAUDE.md` / ADR / `harness-engineering/findings/` に書き出す**。これらは workspace リポ内なので版管理 + push される。
- ツール改善・skill 追加も自走で行う。新規 skill は `.claude/SKILL_INDEX.md` に 1 行追記し、末尾に `effectiveness-log.sh emit` を入れる(`.claude/skill-template.md`)。
- **メモリ(`~/.claude*/.../memory/`)は workspace の外にあり git に含まれない(= push されない)。** ユーザー指摘や再発防止の学びを「リポに残す/共有する」必要があるものは、メモリだけでなく **`findings/` か `CLAUDE.md` にも書く**こと。メモリは個人ローカルの即時想起用、リポは共有の正本、と使い分ける。
- workspace の `master` への commit / push は **Stop フックで自動**(ADR-0005、`harness-autosave.sh`)。ターン内で手動 commit してもよい(意味あるメッセージにしたい時)。

### 8.6 GitHub 接続
- GitHub MCP(`.mcp.json`)を第一選択。MCP で出来ない/不便なときに限り `git` / `gh` をフォールバック許可(理由を commit / PR に残す)。
- ローカル git(`add` / `commit` / `status` / `diff` / `log` / ローカルブランチ切替)は通常通り可。

---

## 9. 補足リンク

- 横断アーキテクチャ → `ARCHITECTURE.md`
- セットアップ → `README.md`
- ハーネス共有設定 → `.claude/README.md`
- スキル索引 → `.claude/SKILL_INDEX.md`
- ハーネス工学(分析・ADR・ツール)→ `harness-engineering/README.md`
- API コントラクト方針 → ADR-0002(`harness-engineering/decisions/0002-api-contract-source-of-truth.md`)
- 既知ドリフトの記録 → `harness-engineering/findings/2026-05-28-openapi-route-drift.md`
