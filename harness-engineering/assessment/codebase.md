# Assessment — コードベース診断(2026-05-28)

AI 駆動開発の観点で釣りログ 2 リポを診断したスナップショット。

---

## tsurilog-native(アプリ)

| 観点 | 状況 | AI フレンドリー度 |
|---|---|---|
| 構造 | `app/`(expo-router file-based)/ `api/`(1 リクエスト 1 ファイル + 型)/ `hooks/`(TanStack Query)/ `components/` / `validation/`(zod)。**規約が一貫**していて読みやすい | 🟢 高 |
| 型 | TypeScript。API クライアントに `*ApiRequestParamsType` / `*ApiResponseType` を定義 | 🟢 高(ただし backend との一致は別途検証要) |
| 状態管理 | サーバ状態 = TanStack Query、グローバル = zustand(トークン程度)。役割分担が明確 | 🟢 |
| スタイル | NativeWind(Tailwind)+ gluestack-ui v3 | 🟢 |
| ai_docs | `ai_docs/`(screens / functions / tech_stack)が既にあり、AI 向け概要が整備されている | 🟢 良い習慣 |
| テスト | 自動テストは実質なし | 🔴 課題 |
| 静的検査 | ESLint + `tsc --noEmit`(`npm run lint`)、Prettier。CI 連携は無し(EAS ビルドのみ) | 🟡 |

**所見:** native は規約が一貫しており AI が新規エンドポイント追加・画面追加をやりやすい。最大の穴は **テスト不在** と **backend との型整合の未保証**。

---

## tsurilog-backend(API)

| 観点 | 状況 | AI フレンドリー度 |
|---|---|---|
| 構造 | **1 エンドポイント 1 コントローラ / public は index のみ**。`Controllers/Api` / `Requests` / `Services`(共有のみ)/ `Models` / `migrations`。規約が README に明文化 | 🟢 高 |
| 規約の明文化 | README に設計思想(Service を作りすぎない等)が書かれている | 🟢 |
| 型/言語 | PHP 8.4 / Laravel 12(モダン) | 🟢 |
| DB | PostgreSQL 16。マイグレーション + マスタ seeder | 🟢 |
| テスト | PHPUnit(`tests/Feature` `tests/Unit`)あり。PR to main で CI 実行。ただしカバレッジは薄い | 🟡 |
| 仕様書 | `openapi.yml` あり。**だが実装とドリフト**(findings 参照) | 🔴 |
| 命名揺れ | 潮汐関連テーブル(`tid_type` / `tid_types` / `tid_type_master` / `tid_action_master`)が混在 | 🟡 |

**所見:** backend は規約が明確で AI が「どこに何を書くか」を迷いにくい(1 エンドポイント 1 コントローラは AI と相性が良い)。穴は **openapi のドリフト** と **テストの薄さ**。

---

## 横断(2 リポ間)

| 観点 | 状況 |
|---|---|
| 結合面 | REST API のみ(DB 共有なし)。横断課題は **API コントラクト**(ADR-0002) |
| コントラクト整合 | 🔴 ドリフトあり(openapi stale 3 / 未記載 13、findings 参照)。app→missing は 0 で 404 バグは現状なし |
| 型整合 | native の API 型 ↔ backend の Request/レスポンスの一致は未検証(機械化されていない) |
| マスタ整合 | 魚種/釣法等は backend seeder が真。native でのハードコード有無は要確認 |
| リポ所有 | native=narita0216 / backend=reomin。権限が分かれている |

---

## AI フレンドリー度まとめ

**強み:**
- 両リポとも規約が一貫・明文化されている(特に backend の 1 エンドポイント 1 コントローラ、native の api/hooks 構造)。
- native に `ai_docs/` が既存。モダンスタック(Laravel 12 / Expo 54)。

**弱み(ハーネスで埋める):**
1. **API コントラクトのドリフト**(最優先)→ `contract-check` + ADR-0002。
2. **テストの薄さ**(両リポ)→ ROADMAP Phase 3。
3. **型整合の未保証** → `api-contract-checker` + カタログ(Phase 2)。
4. 潮汐テーブルの命名揺れ → 調査して ARCHITECTURE に追記。
