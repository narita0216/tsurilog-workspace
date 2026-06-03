# ADR-0009: 釣りの専門知識ハーネス(AI戦略の grounding)

- **Status:** Accepted
- **Date:** 2026-06-03
- **Deciders:** narikei_74
- **Tags:** ai-strategy, prompt, quality, knowledge-base, eval

## Context

AI戦略(Claude)の助言が**日本の釣法の本質を外す**事例が出た。例: ユーザーが「紀州釣り」と指定したのに「中層を攻める」助言が出た。紀州釣りは**底狙い**(糠団子に刺し餌を包んで底まで沈め、団子が割れて出るオキアミ等を海底付近で食わせる)であり、中層主軸は明確な誤り。

原因は、汎用 LLM が個別の釣法(紀州釣り/エギング/サビキ等)の**狙うレンジ・メカニズム**を確実には知らず、一般論で答えてしまうこと。有料提供できる精度に達していない。

## Decision

**「釣法辞典」= 版管理された釣りの専門知識ベースを作り、Claude の system プロンプトに(Prompt Caching して)注入する。** CLAUDE.md がコードベースの AI コンテキストであるように、釣法辞典が AI戦略の専門知識ハーネスとなる。

- **知識ベース**: `tsurilog-backend/resources/ai/fishing-knowledge.md`。各釣法に **主軸レンジ / 本質(メカニズム) / 対象魚 / 仕掛け / 要点 / ありがちな誤り(禁止)** を記述。専門家(オーナー)が追記・修正できる Markdown。
- **注入**: `StrategyService::buildSystemPrompt()` が `config('ai_strategy.system_prompt')`(基本指示+スキーマ)に辞典を連結。`AnthropicClient` が system ブロックに `cache_control: ephemeral` を付けるため、辞典が大きくても**キャッシュで安価**に毎回 grounding できる。
- **厳守ルール**: system プロンプトに「ユーザー指定の釣り方の本質(レンジ・メカニズム)を最優先で尊重し、辞典に該当があれば矛盾する助言をしない(例: 紀州釣りは底狙い、中層を主軸にしない)」を明記。
- **評価ハーネス**: `harness-engineering/tools/ai-strategy-eval.sh`。釣法シナリオ → 実 API → 出力のキーワード判定(例: 紀州釣り→「底/着底/這わせ」を含む)で**重大なズレを回帰検知**。実 Claude を叩く(課金・非決定的)ため、辞典/プロンプト改修時に手動実行。

## Consequences
- **得るもの**: 釣法ごとの正確な助言(紀州釣り→底狙い+団子手順に矯正済み・実機確認)。知識は Markdown で増補容易=有料品質へ継続的に底上げできる。Prompt Caching でコスト増は限定的。
- **失うもの/コスト**: 辞典の保守(網羅性・正確性は専門家レビュー前提)。eval は API 課金が発生。
- **検証(2026-06-03)**: 紀州釣り live で「完全底狙い・ウキ下底ぴったり〜這わせ・糠団子+オキアミ・着底後に割る」を出力(中層主軸の誤り解消)。eval で エギング/サビキ/ジギング/投げ釣り も本質レンジに整合。
- **後戻り可能性**: reversible(辞典の連結を外せば元の挙動)。

## 今後の拡張(品質向上の続き)
- 辞典の網羅拡大(イカ/根魚/磯/船 等)。対象魚の生態(適水温・回遊・時合)も知識化。
- `ANTHROPIC_MODEL_COMPLEX=claude-sonnet-4-6` への引き上げ(難所のみ complex ティア)で推論精度を上げる選択。
- eval のシナリオ拡充 + 「禁止語が主軸か」の判定高度化(現状は粗いキーワード)。

## Related
- 知識ベース: `tsurilog-backend/resources/ai/fishing-knowledge.md`
- 注入: `StrategyService::buildSystemPrompt()` / `config/ai_strategy.php`(`knowledge_path`)
- 評価: `tools/ai-strategy-eval.sh`
- 関連: ADR-0006(AI実行=Laravel内)、initiatives/ai-strategy-feature.md
