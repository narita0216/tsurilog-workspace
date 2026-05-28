# Assessment — ツール / ハーネス状況(2026-05-28)

---

## Claude Code ハーネス(本プロジェクトで構築)

| 要素 | 状況 |
|---|---|
| 横断 `CLAUDE.md` | ✅ 新設(Section 1–9) |
| `ARCHITECTURE.md` | ✅ 新設 |
| `.mcp.json` | ✅ GitHub MCP(Docker) |
| `.claude/settings.json` | ✅ SessionStart / PostToolUse hooks + permissions deny/allow |
| スラッシュコマンド | ✅ 5(`contract-check` / `endpoint-trace` / `backend-check` / `native-check` / `ticket`) |
| サブエージェント | ✅ 3(`laravel-api-reviewer` / `expo-rn-reviewer` / `api-contract-checker`) |
| ツール | ✅ 7(`contract-check` / `php-lint` / `backend-check` / `native-check` / `workspace-sync` / `effectiveness-log` / `harness-autosave`) |
| テレメトリ | ✅ `assessment/effectiveness/events-<host>.jsonl`(自動蓄積) |

---

## MCP

| サーバ | 用途 | 状態 |
|---|---|---|
| github | Issue / PR / ファイル操作 | `.mcp.json` に定義。各メンバーが PAT を export して有効化 |

**注意:** 2 リポの owner が異なる(narita0216 / reomin)。PAT は両方にアクセスできるスコープが必要。

---

## 既存の言語ツール(リポ側)

| ツール | リポ | 用途 |
|---|---|---|
| ESLint / `tsc` / Prettier | native | `npm run lint`(= expo lint + tsc)、`npm run format` |
| Laravel Pint | backend | `./vendor/bin/pint`(整形)/ `--test`(検査) |
| PHPUnit | backend | `php artisan test`(CI でも実行) |
| EAS | native | development / preview / production ビルド(`eas.json`) |
| Docker Compose | backend | api / queue / scheduler / db |

ハーネスツールはこれらを **横断的にまとめて呼ぶラッパー**(`backend-check.sh` / `native-check.sh`)と、リポ側に無い **コントラクト検査**(`contract-check.sh`)を足したもの。

---

## hooks の配線

| タイミング | フック | 効果 |
|---|---|---|
| SessionStart | `workspace-sync.sh check` | 両リポの git 状態(ブランチ/未コミット)を通知 |
| SessionStart | `contract-check.sh --quiet` | コントラクトドリフトがあれば 1 行通知 |
| PostToolUse(Edit/Write/MultiEdit) | `php-lint.sh --hook` | backend `.php` を PHP 8.4 で構文チェック(エラーで blocking) |
| Stop(ターン終了) | `harness-autosave.sh` | workspace の変更を自動 commit & push(ADR-0005) |

native(TS)の型チェックは重いため hook にせず、`/native-check` でオンデマンド(ADR-0004)。

> ⚠️ Stop フック・MCP・deny の変更は **Claude Code 再起動後**に有効化される(settings.json はセッション開始時に読まれる)。

---

## ギャップ / 今後

- コントラクト検査・native 型チェックの **CI 化**(Phase 3)。
- コントラクトの **型レベル突合**(現状はパスのみ。Phase 4)。
- backend critical path の **テスト追加**(Phase 3)。
- 振り返り skill(effectiveness レビュー)は未実装 — ログは貯まっているので必要なら追加。
