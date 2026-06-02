# native dev-client 自動QA(Maestro + スクショ)— 技術メモ & ハマりどころ

- **Date:** 2026-06-02
- **関連:** ADR-0008、`tools/native-qa.sh`、`tools/native-build-needed.sh`、`/native-qa`

AI がスマホアプリ(Expo / dev-client)の動作を自分で確認しスクショを撮る仕組みを入れた際の、調査で判明した事実と落とし穴。

## 1. build 要否は「ネイティブ指紋」で判定する(無料枠温存の核)

- `@expo/fingerprint`(native に v0.15.5 同梱)で判定する。コマンドは:
  ```bash
  tsurilog-native/node_modules/.bin/fingerprint fingerprint:generate --platform ios
  # → JSON。.hash がネイティブ指紋
  ```
- **`expo-updates` は未インストール**なので `npx expo fingerprint:generate` 系の expo CLI サブコマンドは使えない。`@expo/fingerprint` の自前 bin を直接叩く(or `npx --no-install @expo/fingerprint`)。
- 指紋に効くもの = `package.json` のネイティブ依存 / `app.json` / `app.config.ts` / `eas.json` / `*.plist` / `expo-build-properties` / SDK バージョン。**これらが変わらない限り JS/TS をいくら変えても指紋は同じ = build 不要、Metro 配信で反映。**
- 「最後に install した dev-client の指紋」を `assessment/.native-fingerprint-<variant>` にキャッシュ。**マシン依存のローカル状態なので gitignore 済み**(シミュレータに何が入っているかは各マシンで違う)。
- 初回はキャッシュが無いので必ず `needed`。1 度 build + `native-qa.sh install` すればキャッシュが作られ、以降 JS 変更では `skip`。

## 2. 「QRから自動install」はシミュレータでは不要 / 不正確

- QR コードは**実機**で Expo Go / dev-client を開く UX。シミュレータには関係ない。
- シミュレータは `eas build:run -p ios --latest --profile development` で**既にある最新ビルドを DL → install → 起動**できる。これは**ビルド枠を消費しない**(ビルド済み成果物の取得のみ)。
- ただし `eas build:run` で simulator に入れるには、その profile が **simulator 向け `.app`** を出している必要がある。現状 `eas.json` の `development` は `distribution: internal`(=実機 ipa)なので、`"ios": { "simulator": true }` を足す(native 別 PR)。

## 3. 認証(Apple/Google)はシミュレータ自動操作で通せない → dev deep-link 注入

- トークンは `expo-secure-store` の `"accessToken"` キーに保存され、`api-client` が `Authorization: Bearer` を付ける(`hooks/use-auth.ts` / `api/api-client.ts`)。
- SecureStore は iOS Keychain。**外部(simctl)から書き込めない**ので「トークンを事前に流し込む」は不可。
- 解決: dev-client 限定の deep-link ハンドラ `turilog://dev-auth?token=<api_token>` を `app/_layout.tsx` に実装(`__DEV__ && EXPO_PUBLIC_APP_VARIANT==='development'` ガード)。受領したら `setItemAsync("accessToken", token)` + `useAppStore.setAccessToken` してタブへ。**production では完全に無効。**
- Maestro 側は `openLink: "turilog://dev-auth?token=${DEV_API_TOKEN}"` の一発で認証済みにできる。トークンは `maestro -e DEV_API_TOKEN=...` で注入(`TSURILOG_DEV_API_TOKEN` 環境変数経由、ハードコードしない)。

## 4. dev-client を Metro に接続する deep-link

- dev-client は起動しただけだと dev launcher 画面になる。Metro の JS を自動ロードさせるには:
  ```bash
  xcrun simctl openurl booted "turilog://expo-development-client/?url=http://localhost:8081"
  ```
  `<scheme>://expo-development-client/?url=<metro>` の形。scheme は `turilog`。
- ⚠️ **未検証ポイント(初回実機で要確認):** この deep-link 形式・待ち時間(JS バンドルのロード)は環境で揺れる可能性。`native-qa.sh` は `sleep 8` で待っているが、初回実行時に調整して本ファイルに追記すること。

## 5. ハマりどころ・TODO(初回実行で詰める)

- **Maestro の testID:** `flow-template.yaml` の `id: tab-home` 等はプレースホルダ。native の実 `testID` に合わせる(未設定なら native 側に `testID` を足す PR が要る)。
- **Metro の起動完了待ち:** `native-qa.sh` は `http://localhost:8081/status` を polling。port 競合時は `METRO_PORT` で変更。
- **`eas build` は deny + 自走禁止:** `native-qa.sh run` は `needed` で**停止**(exit 20)し案内のみ。実ビルドは人間が明示実行。これは無料枠保護の意図的な設計(ADR-0008)。
- **スクショ PR 添付:** native feature ブランチに `qa-artifacts/<ts>/` を commit → PR 本文に `https://github.com/<owner>/tsurilog-native/blob/<branch>/qa-artifacts/<ts>/xxx.png?raw=true`。squash merge 前提で履歴を汚さない。

## 6. 検証済み / 未検証

- ✅ 検証済み(このマシン): `@expo/fingerprint` の指紋生成、`native-build-needed.sh` の skip/needed 判定とキャッシュ、`native-qa.sh` の全経路(`--dry-run`)とゲート停止(exit 20)。
- ⛔ 未検証(シミュレータ/EAS 未実行): 実 build → `build:run` install、dev-auth deep-link の実挙動、Metro 接続 deep-link、Maestro の実フロー。**初回実機実行時に本ファイルへ結果を追記する。**
