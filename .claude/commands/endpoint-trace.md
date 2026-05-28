---
description: 1 エンドポイントを両リポ横断で追跡(route / controller / request / native client / 型)
argument-hint: "<endpoint or keyword>  例: logs  /records/start  GetDashBoard"
---

`$ARGUMENTS` で指定されたエンドポイント(パスの一部・コントローラ名・機能名いずれでも可)を、アプリと API の両リポにまたがって追跡し、実装の全体像を 1 枚にまとめてください。

## 手順

### 1. backend 側(tsurilog-backend)

```bash
# ルート定義
rg -n "$ARGUMENTS" tsurilog-backend/routes/api.php
# コントローラ(1 エンドポイント 1 コントローラ / index のみ)
rg -ln "$ARGUMENTS" tsurilog-backend/app/Http/Controllers/Api
# バリデーション Request
rg -ln "$ARGUMENTS" tsurilog-backend/app/Http/Requests 2>/dev/null
# レスポンス整形 / 共有 Service
rg -ln "$ARGUMENTS" tsurilog-backend/app/Services 2>/dev/null
# openapi 記載
rg -n "$ARGUMENTS" tsurilog-backend/openapi.yml
```

ルートが分かったら、対応する Controller の `index` を Read して「入力(Request)→ 処理 → レスポンス形」を把握する。

### 2. native 側(tsurilog-native)

```bash
# API クライアント定義(*ApiRequestParamsType / *ApiResponseType)
rg -ln "$ARGUMENTS" tsurilog-native/api
# 呼び出し元の hook(TanStack Query)
rg -ln "$ARGUMENTS" tsurilog-native/hooks
# 画面での利用
rg -ln "$ARGUMENTS" tsurilog-native/app tsurilog-native/components
```

該当する `api/<domain>/<action>.ts` を Read し、リクエスト/レスポンスの TS 型を把握する。

## 出力フォーマット

```
🎣 endpoint-trace: <VERB> /<path>

📡 backend
  - route       : routes/api.php:LINE  (auth: あり/なし)
  - controller  : app/Http/Controllers/Api/<X>Controller.php
  - request     : app/Http/Requests/<X>.php  (主なバリデーション)
  - service     : app/Services/<X>.php  (あれば)
  - openapi     : 記載あり / なし / ズレあり

📱 native
  - client      : api/<domain>/<action>.ts
  - req type    : <*ApiRequestParamsType の主フィールド>
  - res type    : <*ApiResponseType の主フィールド>
  - hook        : hooks/use-<x>.ts
  - 利用画面     : app/...

🔍 整合性の所見
  - パス: native(/api 付き)↔ routes(/api 無し)が一致するか
  - 型: native の req/res と backend の Request/レスポンスが一致するか
  - openapi がこのエンドポイントを正しく記述しているか
```

## effectiveness emit

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome endpoint-trace \
  --details '{"endpoint":"<arg>"}'
```
