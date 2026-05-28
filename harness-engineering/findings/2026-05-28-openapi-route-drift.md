# 2026-05-28 — openapi.yml と実ルート/native のドリフト(初回計測)

ハーネス構築時に `contract-check.sh` を新設して初めて 3 点(`routes/api.php` / `tsurilog-native/api/**` / `openapi.yml`)を機械突合した結果。**ハーネスの存在意義を裏付ける具体例**としてここに記録する。

## 計測コマンド

```bash
harness-engineering/tools/contract-check.sh
```

## サマリ

| 区分 | 件数 | 意味 |
|---|---|---|
| Laravel routes | 35 | 実装の真実 |
| native client calls | 33 | アプリが叩く |
| openapi paths | 20 | 仕様書 |
| 🔴 app→missing route | **0** | アプリが叩くのに無いルート(404)。**無し = 良好** |
| 🟠 openapi stale | **3** | openapi にあるが実ルートに無い |
| 🟡 undocumented | **13** | 実ルートだが openapi 未記載 |
| ⚪ unused by app | 2 | backend にあるがアプリ未使用(`auth/*` = 正常) |

## 🟠 stale(openapi が実装と違う)— 要修正

openapi.yml の analysis 系が実ルートと **名前ごと食い違っている**:

| openapi.yml の記載 | 実ルート(routes/api.php) | native が叩く |
|---|---|---|
| `/analysis/env-data`(ハイフン) | `/analysis/env_data`(アンダースコア) | `/api/analysis/env_data` |
| `/analysis/scores` | (存在しない) | — |
| `/analysis/best-pattern` | (存在しない) | — |
| (記載なし) | `/analysis/condition_stats` | `/api/analysis/condition_stats` |
| (記載なし) | `/analysis/rate` | `/api/analysis/rate` |

→ openapi の analysis セクションは **過去の設計のまま更新されていない**。実装(routes + native)は `env_data` / `condition_stats` / `rate` で一致しているので、**openapi を実装に合わせて書き直す**のが正しい。

## 🟡 undocumented(openapi 未記載の実ルート 13 件)

```
/analysis/condition_stats   /analysis/env_data   /analysis/rate
/auth/google
/dashboard
/fishing_style_master
/notifications   /notifications/read
/push-devices/register   /push-devices/unregister
/settings   /settings/toggle-auto-public   /settings/toggle-notification
```

→ 機能追加(通知・push 端末・設定・ダッシュボード・釣法マスタ)に openapi が追随していない。

## なぜ重要か

- アプリと API は **routes/native では一致している**(app→missing 0)ので、現時点でユーザーに見える 404 バグは無い。
- しかし **openapi.yml が信頼できない状態**で、これを真実だと思って実装/連携すると壊れる。仕様書としての価値が失われている。
- レビューだけでは検出できない。**機械突合(contract-check)で初めて見える**。これがハーネスの中核価値(ADR-0002)。

## 対応

- 即時のバグではないため Issue 化は任意。`initiatives/api-contract-catalog.md` で openapi 同期を進める(Phase 2)。
- 今後 API を触る PR では `/contract-check` を必須化(CLAUDE.md §8.1)。新規エンドポイントは 3 点同時更新。

## 関連
- ADR-0002(API コントラクトの真実)
- initiative: `api-contract-catalog.md`
- ツール: `tools/contract-check.sh`
