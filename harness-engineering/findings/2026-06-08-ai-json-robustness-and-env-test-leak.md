# AI応答のJSON解析失敗を「絶対に出さない」対策 + .env が phpunit に漏れる罠

- 日付: 2026-06-08
- 文脈: dev-client で現地アドバイス生成時に「JSONの解析に失敗」システムエラー。
  併せて Open-Meteo 商用キー設定後にテストが落ちた。

## 1. AI(Claude)応答の JSON 解析を堅牢化

### 症状
`StrategyService::parseStrategyJson` が AI 応答を JSON 化できず `RuntimeException` を投げ、
コントローラまで伝播してユーザーに「システムエラー」が出た。LLM は前置き文・```フェンス・
末尾カンマ・切り詰めなどで容易に壊れた JSON を返す。

### 対策(プロンプト厳格化 + 補修 + フォールバック)
1. プロンプト(`config/ai_strategy.php` system_prompt)の JSON 規約を厳格化
   (必ず `{`〜`}`/ダブルクオート/末尾カンマ禁止/文字列内改行禁止/エスケープ/スキーマ外キー禁止)。
2. **補修**: `salvageJson()` で「最初の `{` 〜 最後の `}`」抽出 + 末尾カンマ除去 → 再デコード。
3. **フォールバック(例外を投げない)**: それでも解釈不能なら `[]` で続行し WARN ログのみ。
   現地は `OnSiteScoreService::compose` が AI出力なし時に観察(config/observation.php)から
   決定論でサマリー/総合評価を補完するため、**ユーザーにはエラーを出さない**。

### ⚠️ assistant プリフィルは使わない(2026-06-08 追記)
当初 `messages` の最後に `['role'=>'assistant','content'=>'{']` を入れて JSON を強制したが、
**一部モデル(Haiku 等)が prefill 非対応で 400**(`This model does not support assistant message prefill.
The conversation must end with a user message.`)になった。**プリフィルは廃止**し、上記
プロンプト厳格化 + 補修 + フォールバックの3点だけで担保する。会話は必ず user で終える。

### 教訓
- LLM に JSON を出させる時は「プロンプトで頼む」だけでは不十分。**パーサで例外を投げない
  (補修+空で続行)**が必須。ユーザー向け機能では「解析失敗 = 空で続行」に倒す。
- **assistant プリフィルはモデル依存**。Anthropic でも非対応モデルがあるので、汎用のJSON強制策に使わない。

## 2. ローカル .env が phpunit テストに漏れる(外部API URL)

### 症状
`OPEN_METEO_*_URL=https://customer-...`(商用)を local `.env` に設定したら、
`GetEnvDataServiceTest`(`api.open-meteo.com` を `Http::fake`)が落ちた
(「2 is identical to 1」= 空応答で天気コードが既定値になった)。

### 原因
`phpunit.xml` で上書きしていない env は、Laravel(immutable Dotenv)が `.env` から読み込む。
SUT は customer URL を叩き、テストの `Http::fake('api.open-meteo.com/*')` に当たらず空応答。

### 対策
`phpunit.xml` の `<php>` で外部APIの URL/キーを**無料エンドポイントに固定**(`force="true"`)。
テストは dev `.env` に依存せず、常に fake が当たる URL になる。

### 教訓
- **テストで `Http::fake` する外部APIの URL は phpunit.xml で固定**する。さもないと開発者の
  `.env`(商用キー・別URL)が漏れて CI/ローカルで不安定化する。
- 関連: [[http-fake-first-match-wins]](Http::fake は先勝ち)。
