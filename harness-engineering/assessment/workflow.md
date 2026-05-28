# Assessment — 開発フロー診断(2026-05-28)

---

## ブランチ・PR

| 項目 | native | backend |
|---|---|---|
| ブランチ | `main` / `develop` / `feature/*`(takeuchi 等の個人 feature 多数) | `main` / `develop` / `feature/*`(narita / takeuchi 等) |
| main 保護 | (要確認) | ✅ PR + テスト通過必須(README 記載) |
| 起点 | `develop` | `develop` |
| リリース | EAS ビルド → ストア | `main` → Apache+Docker デプロイ(`DEPLOYMENT.md`) |

**観察:** feature ブランチが個人名(`feature/takeuchi3` 等)で多数残存。develop 起点・PR 経由の運用は両リポで踏襲できる。

**ハーネス方針:** 新規ブランチは `develop` 起点、`main` 直 push 禁止、PR は人間レビュー(CLAUDE.md §6.1 / settings.json deny)。

---

## CI / 自動化

| 項目 | 状況 |
|---|---|
| backend CI | GitHub Actions `tests.yml`。**PR to main** で Postgres16 + PHP8.4、`migrate` + `php artisan test` | 
| native CI | なし(EAS ビルドのみ) |
| 横断コントラクト検査 | **なし**(本ハーネスで `contract-check.sh` を追加) |
| Lint/型の CI | なし(ローカル `npm run lint` / Pint 任せ) |

**穴:** 
- native の型/lint が CI で守られていない → Phase 3 で CI 化。
- コントラクトドリフトを PR で検出する仕組みがない → Phase 3 で `contract-check` を CI 化。

---

## ローカル開発

| 項目 | 状況 |
|---|---|
| backend | Docker Compose(api/queue/scheduler/db)。`docker-compose.yml` / `docker-compose-local.yml` | 
| native | Expo dev client(Expo Go 不可)。`.env` に `EXPO_PUBLIC_API_DOMAIN` 等 |
| 落とし穴 | `.env.example`(DB=laravel/root)と compose(tsurilog/tsurilog_user)の差 / `localhost` は実機から届かない |

**ハーネス方針:** 動作検証はローカル限定(ADR-0003)。破壊操作は deny。手順整備は `initiatives/local-dev-environment.md`。

---

## タスク管理

- 各コードリポの GitHub Issue / PR(ADR-0001)。
- 横断の調査・決定・発見は `harness-engineering/`。
- リポ所有が分かれている(narita0216 / reomin)ため、PAT スコープを両方に通す必要(`.claude/README.md`)。

---

## まとめ

| 強み | 弱み(ハーネスで埋める) |
|---|---|
| develop 起点・PR 運用が定着 / backend に CI あり | native に CI なし / コントラクト検査が CI に無い / 型・lint が機械保証されていない / ローカル手順が暗黙 |
