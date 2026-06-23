# Decisions (ADR)

釣りログハーネスに関する **重要な意思決定の記録(Architecture Decision Record)** を時系列で残します。「なぜそう決めたか」を後から追えるようにするのが目的。

## 使い方

```bash
cp _template.md 000N-<short-slug>.md
$EDITOR 000N-<short-slug>.md
```

- 番号は連番(`0001`, `0002`, ...)。
- Status は `Proposed` → `Accepted` → 必要なら `Superseded by ADR-XXXX`。
- 決定を覆す場合は古い ADR を消さず、新しい ADR で supersede する。

## 一覧

| ADR | タイトル | Status |
|---|---|---|
| [0001](0001-task-tracking.md) | タスク管理は各コードリポの GitHub Issue | Accepted |
| [0002](0002-api-contract-source-of-truth.md) | API コントラクトの真実は routes/api.php、3 点を揃える | Accepted |
| [0003](0003-local-dev-environment.md) | 動作検証はローカル(backend Docker / native dev client) | Accepted |
| [0004](0004-quality-gates-and-hooks.md) | 品質ゲートと hooks(php-lint / contract-check / Pint / tsc) | Accepted |
| [0005](0005-workspace-autosave.md) | workspace メタリポを Stop フックで自動 commit & push | Accepted |
| [0006](0006-ai-strategy-execution-architecture.md) | AI戦略機能の生成AI呼び出しは既存 Laravel backend 内で実行 | Accepted |
| [0007](0007-env-data-replace-wwo.md) | 環境データ: 天気/海象=Open-Meteo・潮=WWO据え置き・水深=OpenTopoData/GMRT | Accepted |
| [0008](0008-native-ui-qa-devclient.md) | native UI の QA は dev client + Maestro でスクショ(実質E2E) | Accepted |
| [0009](0009-fishing-knowledge-harness.md) | 釣り知識ハーネス(地点md・魚種知識) | Accepted |
| [0010](0010-ai-advisor-onsite-concierge.md) | AIアドバイザー「現地」コンシェルジュ化 | Accepted（ADR-0011で休止） |
| [0011](0011-pivot-to-condition-score-monetization.md) | 記録/AI依存から「釣れる度(一般＋種別課金)」中心へピボット | Accepted |
