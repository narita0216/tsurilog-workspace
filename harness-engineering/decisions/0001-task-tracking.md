# ADR-0001: タスク管理は各コードリポの GitHub Issue

- **Status:** Accepted
- **Date:** 2026-05-28
- **Deciders:** [TBD]
- **Tags:** harness, workflow

## Context

釣りログは `tsurilog-native`(owner: narita0216)と `tsurilog-backend`(owner: reomin)の 2 リポ構成。タスク・バグ・TODO の置き場所を決めないと、AI も人間も「どこを見れば作業の全体像が分かるか」が定まらない。

airtrunk では「workspace 専用の GitHub Issue リポ」を Claude 用のタスク置き場にしていたが、釣りログのワークスペース親は現時点で GitHub リポを持たない(ローカルディレクトリ)。

## Options

### Option A: 各コードリポの GitHub Issue をそのまま使う
- **Pros:** 既存運用。PR と同じリポで完結。owner/レビュアーが自然に見える。
- **Cons:** 横断タスク(両リポにまたがる)をどちらに置くか曖昧。

### Option B: workspace 用の新規 GitHub リポを作って Claude 用タスク置き場にする(airtrunk 方式)
- **Pros:** 横断タスクの一元管理。AI の調査ログを集約。
- **Cons:** リポ新設・権限設定のコスト。2 owner 構成で置き場所が増えて複雑。

### Option C: 何もしない
- タスクの所在が人依存のまま。AI が毎回探す。

## Decision

**Option A を採用する。** タスク・バグ・TODO は **実装するコードのあるリポの GitHub Issue / PR** で管理する。横断的な調査ログ・意思決定・発見は `harness-engineering/`(`findings/` / `decisions/` / `initiatives/`)に置く。

横断タスクは「主たる変更が入るリポ」の Issue に立て、本文に対のリポへの影響を書く。

## Consequences
- **得るもの:** 既存運用を壊さず、PR とタスクが同じリポに揃う。
- **失うもの:** 横断タスクの一元ビューはない(Issue を 2 リポ横断で見る必要あり)。
- **新たに発生する作業:** `/ticket <repo>#<n>` で repo を明示して読む運用。
- **後戻り可能性:** reversible(後から Option B に移行可)。

## Related
- `/ticket` コマンド(`.claude/commands/ticket.md`)
- CLAUDE.md §6.0
