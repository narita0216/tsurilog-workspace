# 個人AIハーネス Phase 1(自分専用AI + 独自知識)実装メモ

- 日付: 2026-06-03
- 対象: tsurilog-backend / tsurilog-native(両方 `feature/ai-strategy`)
- 関連: `initiatives/ai-strategy-feature.md`、ADR-0009(釣法辞典ハーネス)、`findings/2026-05-29-env-data-wwo-only-no-terrain.md`

## なぜやるか(意思決定の経緯)

AI戦略は一般論なら commodity 化する。釣りログは**リリース直後でユーザ約40人・釣果データがほぼ無い**ため、自前DBに依拠した「データの堀」は当面作れない(cold-start)。さらに**無料提供は使われるほど API コストで赤字**になる。

→ 方針転換:
1. まず**無料の外部データでローカル感を限界まで出す**(Open-Meteo / GEBCO水深 / 既知釣り場500点の最寄り地名 = 既存実装)。
2. その上で**ユーザ自身がAIを育てるプラットフォーム**にする。釣りが上手い人ほど自分の現場知識を教え込み、検証のために釣行が増え、結果データも増える循環を狙う。
3. 収益化 = 自作AIの作成・利用を**月額課金(プレミアム)限定**にする。

ユーザの確定要件:
- 「**新規作成するAIに名前をつけて作成でき、戦略作成画面でどのAIを使用するかを選択できる(釣りログ標準AIと自分の作ったAIから選択)**」= **エージェント中心モデル**。
- 知識の教え込みは会話/フィードバックではなく**構造化フォーム登録**(ユーザ選択)。

## データモデル(agent-centric)

```
users 1──* ai_agents 1──* ai_user_knowledge
                   └─ ai_strategies.ai_agent_id (null = 釣りログ標準AI)
```

- `ai_agents`: user_id / name(50) / description(255,任意) / is_active / softDeletes
- `ai_user_knowledge`: **ai_agent_id 紐付け**(user 直下ではない) / title / fish_id? / fishing_style?(自由入力) / lat? / lng? / spot_label? / body(2000) / is_active / softDeletes
- `ai_strategies.ai_agent_id`: どのAIで生成したか(nullableOnDelete)

## 知識の関連抽出 → プロンプト注入(精度の肝)

`UserKnowledgeService::relevantFor(AiAgent, fishId?, fishingStyle?, lat, lng, limit=8)`:
- 魚種: 指定があり別魚種の知識は**除外**。一致 +3。null(汎用)は対象。
- 釣法: 部分一致(自由入力同士) +2。
- 地点: ≤3km +4 / ≤10km +2 / ≤30km +0.5 / >30km は**除外**。lat/lng 無し(汎用) +0.5。
- スコア降順で上位N件。

`StrategyService::buildContext` の**末尾(最も salient な位置)**に
`# あなた専用の知識「{AI名}」(最優先で活用)` ブロックを差し込み、「一般論より優先、矛盾時はこちらを採用」と明示。base 釣法辞典(system / Prompt Caching)より優先させる。

## API(1エンドポイント1コントローラ厳守)

| メソッド | パス | 備考 |
|---|---|---|
| GET | `/ai-agents` | 一覧(knowledge_count 付き) |
| POST | `/ai-agents` | 作成。**is_premium 必須** + 作成上限(`ai_strategy.max_agents`=5) |
| PUT/DELETE | `/ai-agents/{id}` | 所有者のみ。delete はソフト |
| GET/POST | `/ai-agents/{agentId}/knowledge` | 知識上限(`max_knowledge_per_agent`=100) |
| PUT/DELETE | `/ai-agents/{agentId}/knowledge/{id}` | |

- pre-trip / on-site に nullable `ai_agent_id`。**未所有/無効AIは is_success=false で拒否**(黙って標準AIにフォールバックしない)。
- 所有解決は `AiAgent::owned()`(有効無効問わず・知識管理用)/ `ownedActive()`(戦略用・null=標準)。
- openapi.yml に AI Agent パス・スキーマを追記済み(`/contract-check` で 4 パス解決、残ドリフトは既存分のみ)。

## native

- `api/ai-agent/*`(1リクエスト1ファイル) / `hooks/use-ai-agent.ts`(TanStack Query)
- `app/ai-strategy/agents.tsx`(一覧・作成・削除、非プレミアムは作成不可UI)
- `app/ai-strategy/agent-knowledge.tsx`(構造化フォーム: 見出し/内容/魚種/釣り方/スポット地図長押し)
- `components/ai-strategy/agent-select.tsx`(戦略画面のAI選択チップ)→ pre-trip/on-site に組込み、ハブにも導線。
- スタイルは既存どおり 100% StyleSheet + ダークテーマ定数。lint + tsc green。

## 落とし穴・学び

- **Pint は本リポの gate ではない**: `pint.json` 無し(default preset)、CI(tests.yml)に Pint ステップ無し。かつ**既存コミット済みコードも default preset に非準拠**(`single_line_empty_body` / `@package` phpdoc / `concat_space` 等で軒並み FAIL)。よって新規ファイルは Pint auto-fix を**かけず**、既存実装の作法に合わせた(空コンストラクタは複数行・`@package` phpdoc 維持)。`/backend-check` で Pint を回すと大量の既存差分が出るのは想定どおり。
- **phpunit は RefreshDatabase でローカル dev DB を毎回 wipe**(既知)。テスト後は qa_tester(`00000000-0000-4000-8000-000000000001`、本機能の検証用に **is_premium=true** で再作成)を必ず復旧する。
- 全205テスト green(新規 AiAgentEndpointTest 7件含む)。CRUD はローカル docker に live curl で疎通確認済み。知識注入の検証は Http::fake で user メッセージ本文に知識本文・AI名・「最優先」が含まれることを assert(実Claudeトークンをローカルで消費しない)。

## 実コスト(2026-06-04 実測・Sonnet・コールド)

実 API で計測（grounding込みの本番同等プロンプト）:

| 機能 | フル辞典 | RAG-lite(辞典を関連分だけ) |
|---|---|---|
| 事前戦略(Sonnet) | **¥13.6**($0.085) | ¥8.7 |
| 現地戦略(Gemini Flash動画+Sonnet) | **¥13.8** | ~¥8.9 |

- **Gemini Flash の動画解析はほぼ無料**: 15秒clipで promptToken 4,756(video 4,208/audio 481)・出力69 = **¥0.26**。1分でも¥1未満。→ 「現地は3〜6倍高い」は誤りで、**事前≒現地≒同原価**(あなたの「事前=現地で同数」は原価的にも正しい)。
- コストの主役は **Sonnet 呼び出し、特に辞典(約16kトークン)のキャッシュ書込($3.75/M)= 全体の約7割**。出力(~1,500tok)が約3割。
- **プロンプトキャッシュは5分TTL・内容ベースでユーザー横断共有**。コールドで¥13.6、5分以内の2回目(キャッシュ読込$0.30/M)なら¥4.8。規模が出れば辞典コストは自然に薄まる。1時間TTLは書込2倍なので「まばら頻度」のときだけ得=今は5分のまま。
- モデル別の事前1回目安: Haiku ≈¥5 / Sonnet ≈¥13.6(実測) / Opus ≈¥60〜70。
- **RAG-lite(関連セクション抽出)で▲36%**だが、釣法はフリーテキストで抽出が難物（魚は fish_id で完全一致可）。プラン自体はフル辞典でも黒字なので **RAG は今やらない**。まず実コストロギングで読込率を観測してから判断。

### プラン economics(Sonnet・実測ベース)
- 無料: 事前 **生涯3回**(原価 一度¥24/人)。
- ライト **¥500** / 事前10・現地10(月20): 最大原価 ~¥274(RAG-liteで~¥176)、手取り¥350〜425 → **黒字**。
- スタンダード **¥1,200** / 30・30: 最大原価 ~¥822(RAG ~¥528)、手取り¥840〜1,020 → 黒字。
- Opus は¥500では不可。Max プラン専用＋A/Bで「5倍の価値」を検証してから。

### 実コストロギング(実装済み・2026-06-04)
`ai_strategies` に Claude/Gemini の生トークンを記録(`input/output/cache_write/cache_read_tokens`、`gemini_prompt/output_tokens`)。円換算は BI 側。`AnthropicClient::lastUsage()` / `GeminiClient::lastUsage()` で応答の usage を拾い `StrategyService` が保存。本番で実平均原価・キャッシュ読込率が取れる。Redash 例:
```sql
select kind, model, count(*) n,
       avg(input_tokens) in_avg, avg(output_tokens) out_avg,
       avg(cache_read_tokens) cr_avg, avg(cache_write_tokens) cw_avg,
       -- Sonnet単価で円換算(単価は要メンテ)
       avg((input_tokens*3 + cache_write_tokens*3.75 + cache_read_tokens*0.30 + output_tokens*15)/1e6*160) jpy_avg
from ai_strategies where created_at > now() - interval '30 days'
group by kind, model;
```

## ブランチ/コミット状況

- backend(reomin 所有): `feature/ai-strategy` に**ローカルコミットのみ**(push は所有者)。
- native(narita0216): `feature/ai-strategy` に commit + **push 済み**。
- 動作確認・レビュー後にそれぞれ develop への PR を立てて人間レビュー → リリース。
