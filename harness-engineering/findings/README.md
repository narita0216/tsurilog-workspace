# Findings

作業・調査・実装中に判明した **非自明な事実・落とし穴・参考情報** を時系列で蓄積します。

## 命名規則

```
YYYY-MM-DD-<topic>.md
例: 2026-05-28-openapi-route-drift.md
```

## findings と他の置き場所の使い分け

| 内容 | 置き場所 |
|---|---|
| 一次的な発見・ハマりどころ | **findings/**(ここ) |
| 定着した運用ルール・意思決定 | `decisions/`(ADR) |
| 進行中の取り組みの計画と進捗 | `initiatives/` |
| 現状の構造的な診断 | `assessment/` |

発見が運用ルールに昇格したら ADR を立て、findings からリンクする。

## 一覧

| 日付 | トピック |
|---|---|
| [2026-05-28](2026-05-28-openapi-route-drift.md) | openapi.yml と実ルート/native クライアントのドリフト(初回計測) |
