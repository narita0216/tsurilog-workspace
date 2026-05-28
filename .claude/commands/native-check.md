---
description: tsurilog-native の品質ゲート(expo lint + tsc --noEmit + Prettier)
argument-hint: "(任意) types | format | format:check"
---

`tsurilog-native` の品質チェックを実行します。Expo SDK 54 / React 19 / TypeScript。native を触る PR の前に必ず通す。

## 0. 前提

```bash
# node_modules があること
ls tsurilog-native/node_modules >/dev/null 2>&1 || ( cd tsurilog-native && npm install )
```

## 1. 実行

```bash
harness-engineering/tools/native-check.sh $ARGUMENTS
```

| 引数 | 動作 |
|---|---|
| (なし) | `npm run lint`(= `expo lint` + `tsc --noEmit`) |
| `types` | `tsc --noEmit` のみ(型エラーだけ素早く見たい時) |
| `format` | `prettier . --write`(**書き込みあり**) |
| `format:check` | `prettier . --check`(非破壊) |

## 2. 結果の扱い

- **型エラー(tsc)** は最優先で修正。`any` で握り潰さない。特に API クライアントの `*ApiRequestParamsType` / `*ApiResponseType` は backend の実装と一致させる(疑わしければ `/endpoint-trace`)。
- **ESLint 警告** は既存ルール(`eslint.config.js`)に従って修正。
- **Prettier 差分** は `format` で整形してコミット。

## 3. 規約リマインド(詳細は expo-rn-reviewer)
- `api/<domain>/<action>.ts` に 1 リクエスト 1 ファイル + 型定義
- サーバ状態は TanStack Query(`hooks/use-*.ts`)、フォームは react-hook-form + zod
- スタイルは NativeWind(className)。画面は expo-router(`app/`)
- 魚種/釣法 ID をハードコードしない(master API / 定数を参照)

## 4. UI を変えたら
可能なら dev client(`npx expo start --dev-client`)で実機/シミュレータ確認。できない場合はその旨を PR / 報告に明記する(型・lint が通る ≠ 画面が正しい)。

## 5. effectiveness emit

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome native-check
```
