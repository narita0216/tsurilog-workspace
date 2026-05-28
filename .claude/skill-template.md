---
description: <この skill の主目的を 1 行で>
argument-hint: <例: "<endpoint> 任意の追加コンテキスト">
---

<!--
  Skill テンプレ — 新しい slash command (`.claude/commands/<name>.md`) を作るときは
  これをコピーして使う。

  必須要件:

  1. 末尾に effectiveness-log.sh の `emit invoke` を必ず入れる。
     これが無いと死蔵 skill 検出ができない(Claude Code には skill 起動 hook が
     無いため、skill 自身が emit する以外に集計手段が無い)。

  2. 新しい skill を作ったら `.claude/SKILL_INDEX.md` の表に 1 行追記する
     (CLAUDE.md §8.5)。

  3. ファイル配置は `.claude/commands/<kebab-name>.md`(必ず commands/ 配下)。
     `.claude/` 直下に置くと slash command として登録されない。

  4. API(routes / native api / openapi)を生成・編集する skill なら、
     `/contract-check` を呼ぶ手順を組み込む(ADR-0002)。
     PHP を触るなら php-lint.sh、TS を触るなら native-check.sh。

  5. 不可逆操作(push --force / reset --hard / migrate:fresh / 履歴書き換え)は
     書かない。CLAUDE.md §8.4。
-->

<skill の目的・流れをここに記述>

## 0. 前処理

(任意 — workspace-sync / contract-check / ブランチ確認など)

## 1. 主処理

(skill の本体ロジック)

## 2. 出力フォーマット

(stdout に何を出すか、PR 本文に何を貼るか)

## 3. effectiveness emit(必須)

skill 末尾で必ず以下を実行する(自然文で書いて Claude が bash 実行する):

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome <skill-kebab-name> \
  --details '{"result":"<short outcome>"}'
```

## 4. 失敗時の振る舞い

(skill が途中で詰まった時、何を残して人間 / 次の Claude に handoff するか)
