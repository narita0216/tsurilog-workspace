# ADR-0006: AI戦略機能の生成AI呼び出しは既存 Laravel backend 内で実行する

- **Status:** Accepted(PoC で再評価あり)
- **Date:** 2026-05-29
- **Deciders:** narita
- **Tags:** ai, architecture, backend, security

## Context

AI戦略作成機能(事前戦略 / 現地戦略、`initiatives/ai-strategy-feature.md`)では、Claude API(戦略立案)
と Gemini API(現地動画解析)を呼び出し、釣りログ DB と外部環境 API(WWO / NOAA・海保 / 既存潮汐)の
データを束ねて戦略を生成する。この**生成 AI オーケストレーションをどこで動かすか**を決める必要がある。

前提・制約:
- 既存認証は自前 Bearer トークン(`users.api_token` + `auth.apitoken` ミドルウェア、CLAUDE.md §4)。JWT は未使用。
- native は秘密を持てない(クライアント)。AI / 外部 API キーをアプリに置くのは漏洩リスク。
- backend は PHP 8.4 / Laravel 12。CLAUDE.md §8.2 に Laravel コード規約あり。
- 要件タスク AI-2(技術スタック選定)・AI-3(JWT発行・検証)はこの決定に依存する。

## Options

### Option A: 既存 Laravel backend 内で実行(採用)
- Laravel から Claude/Gemini を HTTP 呼び出し。API キーは backend `.env` のみ。native は backend 経由のみ。
- 認証は既存 Bearer(`auth.apitoken`)を流用 → **JWT 不要(AI-3 は再定義)**。
- Prompt Caching・モデル振り分け・会話履歴・レート制限も Laravel 側に実装。
- **Pros:** secrets 一元管理。既存認証・DB・規約をそのまま流用。運用面が増えない。CLAUDE.md 規約に最も整合。
- **Cons:** PHP で AI SDK の最新機能(ストリーミング等)を扱う際、公式 SDK の成熟度が言語により劣る場合あり(HTTP 直叩きで回避可)。長時間処理が web リクエストを占有 → queue / 非同期化の検討要。

### Option B: AI 専用の別サービス(Node / Python 等)
- AI オーケストレーション専用サービスを分離。Laravel とはサービス間認証(ここで JWT が要る = AI-3 の意図候補)。
- **Pros:** AI SDK エコシステムが厚い言語を選べる。スケール・デプロイを独立可。技術分離。
- **Cons:** インフラ・デプロイ・サービス間認証・監視が増える。secrets が 2 系統に。小規模チームに運用負荷大。CLAUDE.md の単一 backend 前提から逸脱。

### Option C: native から直接 AI API を叩く
- **Pros:** backend 実装不要。
- **Cons:** **却下。** API キーがクライアントに乗り漏洩・濫用リスク。レート制限/課金/会話履歴をサーバ管理できない。

## Decision

**生成 AI 呼び出しは既存 Laravel backend 内で実行する(Option A)。** secrets は backend に一元化し、
native は backend 経由のみ。認証は既存 Bearer を流用し、AI-3 の「JWT 発行・検証」は不要として再定義する。
将来 AI 処理がスケール上のボトルネックになれば別サービス分離(Option B)を改めて検討する(後戻り可能)。

## Consequences

- **得るもの:** secrets 一元管理・既存認証/DB/規約の流用・運用面の単純さ。
- **失うもの:** PHP での AI SDK 利便性(HTTP 直叩き or コミュニティ SDK で補う)。
- **新たに発生する作業:** Laravel での Claude/Gemini HTTP クライアント実装、長時間処理の非同期化方針(queue 活用)検討、レート制限・会話履歴の DB 設計。
- **後戻り可能性:** reversible(オーケストレーションを別サービスへ切り出すのは後からでも可能)。

## Related
- 関連イニシアチブ: `initiatives/ai-strategy-feature.md`
- 関連 ADR: ADR-0002(API コントラクト)・ADR-0004(品質ゲート)
- 要件タスク: AI-2(技術選定= Laravel)・AI-3(JWT → 不要に再定義)
