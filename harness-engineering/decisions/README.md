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
