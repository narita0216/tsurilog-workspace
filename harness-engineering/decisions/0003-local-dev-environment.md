# ADR-0003: 動作検証はローカル(backend Docker / native dev client)

- **Status:** Accepted
- **Date:** 2026-05-28
- **Deciders:** [TBD]
- **Tags:** harness, local-dev, safety

## Context

AI による動作検証・実装を、本番や共有環境で試すのは事故リスクが高い(データ破壊・通知の誤配信・ストア提出など)。釣りログには以下のローカル手段が揃っている:

- **backend**: Docker Compose(`api` / `queue` / `scheduler` / `db=postgres16`)。`docker-compose-local.yml` も用意。
- **native**: Expo dev client(`npx expo start --dev-client`)。Expo Go では動かない(カスタムネイティブコードあり)。

## Options

### Option A: 動作検証はローカルに限定(本番/共有への直接接続を禁止)
- **Pros:** 破壊・誤配信のリスクを排除。再現性が高い。
- **Cons:** ローカル構築の初期コスト(Docker / EAS dev client)。

### Option B: staging で検証
- **Pros:** 本番に近い。
- **Cons:** 共有環境の汚染・並行作業の衝突。釣りログに明確な staging があるか不明([TBD])。

### Option C: 制限しない
- AI が本番 DB / 通知 / ストアに触れる退路が残る。許容不可。

## Decision

**Option A を採用する。** 動作検証・実装は **ローカルで完結**させる。backend は Docker Compose、native は dev client。本番・共有環境への直接書き込みや試行は行わない。

危険操作はハーネスで物理的に塞ぐ(ADR-0004 / settings.json deny):`migrate:fresh` / `migrate:reset` / `db:wipe` / `docker compose down -v` / `eas submit` / `eas build` を deny。

## Consequences
- **得るもの:** 安全な反復。AI に動作確認を任せられる。
- **失うもの:** ローカル環境の準備が前提になる(未構築だとコード変更タスクに着手しづらい)。
- **新たに発生する作業:** ローカル構築手順の整備(`initiatives/local-dev-environment.md`)。判明した落とし穴は `findings/`。
- **後戻り可能性:** reversible。

## Related
- initiative: `local-dev-environment.md`
- ADR-0004(deny ルール)
- CLAUDE.md §8.0 / §8.4
- `tsurilog-backend/README.md` / `DEPLOYMENT.md` / `tsurilog-native/README.md`
