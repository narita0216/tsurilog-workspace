---
description: tsurilog-backend の品質ゲート(Laravel Pint + PHPUnit を Docker で実行)
argument-hint: "(任意) pint | pint:fix | test [テスト引数]"
---

`tsurilog-backend` の品質チェックを Docker Compose の `api` コンテナ内で実行します。Laravel 12 / PHP 8.4。backend を触る PR の前に必ず通す。

## 0. 前提

backend のコンテナが起動していること:

```bash
docker compose -f tsurilog-backend/docker-compose.yml ps
# 起動していなければ
( cd tsurilog-backend && docker compose up -d )
```

## 1. 実行

```bash
harness-engineering/tools/backend-check.sh $ARGUMENTS
```

| 引数 | 動作 |
|---|---|
| (なし) | Pint `--test`(非破壊スタイル検査)+ `php artisan test` |
| `pint` | Pint `--test` のみ |
| `pint:fix` | Pint 自動整形(**書き込みあり**) |
| `test [args]` | `php artisan test [args]`(例: `test --filter=test_can_create_log_successfully`) |

## 2. 結果の扱い

- **Pint で差分が出たら** `backend-check.sh pint:fix` で整形し、差分を確認してコミット。
- **テストが落ちたら** 失敗ケースを読み、原因を特定して修正。テストを安易に skip しない。
- 設計規約(1 エンドポイント 1 コントローラ / public は index のみ / バリデーションは Request / Service は共有処理のみ)に反する実装をしていないか、レビュー観点は `laravel-api-reviewer` サブエージェントを参照。

## 3. 注意
- `migrate:fresh` / `db:wipe` はローカル DB を全消去するため使わない(deny 済み)。スキーマ確認は `php artisan migrate:status`。
- PHP 編集時は PostToolUse hook(`php-lint.sh`)が構文を自動チェックしている。本コマンドはその先の整形・テスト層。

## 4. effectiveness emit

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome backend-check
```
