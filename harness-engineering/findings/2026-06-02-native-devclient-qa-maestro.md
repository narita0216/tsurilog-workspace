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
- 初回はキャッシュが無いので必ず `needed`。1 度 build すればキャッシュが作られ、以降 JS 変更では `skip`。

## 2. ★最重要の訂正: シミュレータQAのビルドは「ローカル `expo run:ios`」= EAS 枠を消費しない

当初 EAS build(枠消費)を前提に設計したが、**シミュレータ用 dev-client はローカル Xcode ビルドで完結でき、EAS の無料枠を一切消費しない**。これが「ビルド回数/枠を最小化したい」要件に最も適う。

- **`npx expo run:ios --device <udid>`** が prebuild → pod install → xcodebuild → simulator に install + 起動 + Metro 起動まで行う。**EAS クレジット消費ゼロ。** `eas build` は deny 対象だが `expo run:ios` は対象外 = **AI が自走で実行できる**。
- → `native-qa.sh build`(`do_build`)がこれを担う。`run` の build要否 gate は `needed` のとき「`native-qa.sh build` を実行せよ」と促す(ローカルビルドは無料だが ~10-25分と長いので run 内では自走しない)。
- **EAS build は実機配布 / EAS 成果物が要るときだけ**。`eas build:run`(DL+install、枠消費なし)は `native-qa.sh install` に残す。
- 「QRから自動install」は実機の UX。シミュレータには無関係(ローカルビルドが直接 install する)。
- `eas.json` に足した `development-simulator`(simulator:true)は EAS でシミュレータビルドを作る場合のみ必要。ローカル `expo run:ios` では使わない(が、入れておいて損はない)。

## 2b. ローカルビルドの環境ハマりどころ(2026-06-02 実機で遭遇)

このマシン(x86_64 / Intel `/usr/local` Homebrew + macOS 15)で `expo run:ios` が `pod install` で失敗:
- **CocoaPods の ffi アーキ不整合:** `dlopen(...ffi-1.15.5/ffi_c.bundle): incompatible architecture (have 'arm64', need 'x86_64')`。system Ruby(`/usr/bin/ruby`, gem cocoapods 1.15.2)の ffi gem が壊れていた。
  - **対処:** `brew install cocoapods`(自己完結、1.16.2)を入れ、**PATH 前置**で system の壊れた pod(`/usr/local/bin/pod`, root 所有でシャドウ)より優先させる → `native-qa.sh` の `ensure_cocoapods()` が自動化。
- **maestro は JDK 必須:** `brew install mobile-dev-inc/tap/maestro`(openjdk を依存で入れる)。ただし brew openjdk は keg-only で `JAVA_HOME` 未通 → `native-qa.sh` の `ensure_java()` が `brew --prefix openjdk` から自動設定。
- **maestro の名前衝突に注意:** `brew install maestro`(タップ無し)は**別物**(runmaestro.ai の "AI agent command center")を入れる。モバイルテスト用は必ず `mobile-dev-inc/tap/maestro`。
- **`curl | bash` インストーラはハーネスの安全分類でブロックされる** → brew 経由が正。

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
