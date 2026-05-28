# ADR-0004: 品質ゲートと hooks(php-lint / contract-check / Pint / tsc)

- **Status:** Accepted
- **Date:** 2026-05-28
- **Deciders:** [TBD]
- **Tags:** harness, quality, hooks, telemetry

## Context

AI のアウトプットを機械検証する層がないと、片側修正・型不一致・構文エラーが PR まで通ってしまう。釣りログには 2 言語(PHP / TypeScript)+ コントラクトという 3 つの検証軸がある。どこを「自動(hook)」にし、どこを「オンデマンド(コマンド)」にするかを決める。

## Options

### Option A: 速い検査は hook で自動化、重い検査はオンデマンド
- **Pros:** 編集の都度の摩擦を最小化しつつ、致命的な誤りは即ブロック。
- **Cons:** どの検査をどちらにするかの線引きが必要。

### Option B: 全部 hook(編集の都度 lint + 型 + テスト)
- **Pros:** 漏れない。
- **Cons:** `tsc --noEmit` や PHPUnit は重く、編集ごとに走ると遅くて邪魔。

### Option C: 全部オンデマンド(hook なし)
- **Pros:** 摩擦ゼロ。
- **Cons:** AI が検査を忘れると素通り。

## Decision

**Option A を採用する。** 線引きは以下:

**自動(hooks / settings.json):**
- **SessionStart**: `workspace-sync.sh check`(両リポ git 状態)+ `contract-check.sh --quiet`(コントラクトドリフト通知)。どちらも軽量・docker 不要。
- **PostToolUse(Edit/Write/MultiEdit)**: `php-lint.sh --hook` — `tsurilog-backend/` 配下の `.php` のみ Docker `php:8.4-cli` で `php -l`。構文エラーは exit 2 でブロック。Docker 不在なら silent skip。**native(TS)は重いので hook にしない**。

**オンデマンド(コマンド):**
- `/contract-check`(全レポート / `--strict`)
- `/backend-check`(Pint `--test` + PHPUnit、Docker `api` コンテナ)
- `/native-check`(`expo lint` + `tsc --noEmit`、+ Prettier)

**テレメトリ:** 各ツールは `effectiveness-log.sh` で実行結果を `assessment/effectiveness/events-<host>.jsonl` に蓄積し、死蔵 skill / 繰り返し失敗を後から振り返れるようにする。

**危険操作の deny:** `migrate:fresh` / `migrate:reset` / `db:wipe` / `docker compose down -v` / `eas submit` / `eas build` / 各種破壊的 git を `permissions.deny` で禁止(ADR-0003)。

## Consequences
- **得るもの:** PHP 構文エラー・コントラクトドリフトを早期検出。重い検査は PR 前にまとめて。使用統計が貯まる。
- **失うもの:** native の型チェックは自動化されない(忘れると素通り)→ CI 化を Phase 3 で。
- **新たに発生する作業:** ツールの保守。hook が静かに壊れていないかの確認。
- **後戻り可能性:** reversible(hook は settings.json で着脱可)。

## Related
- ツール: `tools/*.sh`、`.claude/settings.json`
- コマンド: `/contract-check` `/backend-check` `/native-check`
- CLAUDE.md §8.2 / §8.3 / §8.4
- ROADMAP Phase 3(CI 化)
