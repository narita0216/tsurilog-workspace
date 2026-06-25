# Initiatives

進行中の個別の取り組みを 1 ファイル 1 イニシアチブで管理します。計画 + 進捗を同じファイルに置き、状態が変わったら追記更新する。

## 使い方

```bash
cp _template.md <slug>.md
$EDITOR <slug>.md
```

## 一覧

| イニシアチブ | 目的 | Status |
|---|---|---|
| [api-contract-catalog](api-contract-catalog.md) | エンドポイント別の routes/native/openapi 3 点対応表を作る | 🟡 進行中 |
| [local-dev-environment](local-dev-environment.md) | backend Docker / native dev client のローカル環境を確実に立ち上げ、手順を整備 | 🟡 進行中 |
| [ai-strategy-feature](ai-strategy-feature.md) | 事前戦略 / 現地戦略の AI 機能(Claude+Gemini×釣りログDB×環境データ) | ⏸ 休止(ADR-0011でピボット) |
| [2026-06-pivot-condition-score-monetization](2026-06-pivot-condition-score-monetization.md) | 釣れる度(一般＋種別課金¥150)ピボット。記録/AI依存をやめ磁石+深さ課金へ(ADR-0011) | 🟡 進行中 |
| [condition-score-redesign-requirements](condition-score-redesign-requirements.md) | 釣れる度 再設計の確定要件(一般主体・絶対値・データ自動成長shrinkage)。A2/A3 実装要件 | ✅ 1.1.2 実装済 |
| [2026-06-1.1.3-species-score-and-admob](2026-06-1.1.3-species-score-and-admob.md) | 1.1.3 要件: 魚種ごと釣れる度(¥300サブスク)＋AdMob改善 | ✅ 要件定義完了 |
