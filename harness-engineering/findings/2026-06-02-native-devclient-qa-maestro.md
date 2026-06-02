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

## 4. dev-client を Metro に接続する deep-link(★2026-06-02 実機確認)

- dev-client は起動しただけだと dev launcher 画面になる。Metro の JS をロードさせるには:
  ```bash
  xcrun simctl openurl booted "exp+turilog://expo-development-client/?url=http://localhost:8081"
  ```
  **スキームは `exp+turilog://`(app scheme の `turilog://` ではない!)。** expo-dev-client が
  `exp+<scheme>` を登録する。`turilog://expo-development-client` では繋がらない。
- **`simctl openurl` は iOS の確認ダイアログ「"釣りログ" で開きますか?」(キャンセル/開く)を出す。**
  → Maestro 側で最初に `開く` をタップして通過する(qa.yaml の runFlow で実装済み)。
- **初回 JS バンドルは ~60-90s** かかる(スプラッシュ→"Bundling NN%"→アプリ描画)。2 回目以降は
  Metro キャッシュで速い。待ちは「dev launcher の "DEVELOPMENT SERVERS" が消えるまで」で判定。
- dev メニュー(`Reload`/`Connected to:` 等)が出ることがある → 画面上部余白タップで閉じる。

## 5. ハマりどころ・TODO

- **Maestro の testID:** native に testID が無いため、タブは**表示テキスト**(「ホーム」「マップ」
  「釣行記録」「プロフィール」)でセレクトしている。安定運用には testID を足すのが望ましい。
- **Metro の起動完了待ち:** `native-qa.sh` は `http://localhost:8081/status` を polling。port 競合時は `METRO_PORT`。
- **ローカルビルドは無料・自走可:** `native-qa.sh build`(= `expo run:ios`)。`eas build`(枠消費)は deny + 自走禁止。
- **スクショ PR 添付:** native feature ブランチに `qa-artifacts/<ts>/` を commit → PR 本文に `https://github.com/<owner>/tsurilog-native/blob/<branch>/qa-artifacts/<ts>/xxx.png?raw=true`。squash merge 前提で履歴を汚さない。
- **`expo run:ios` の最終ステップ(`osascript` で Simulator 窓を前面化)は AppleScript 自動化権限が無い env で失敗するが、`.app` の install は完了している**(無視してよい)。アプリ起動は `xcrun simctl launch` で代替。

## 6. 検証済み / 未検証(2026-06-02 実走で更新)

- ✅ **検証済み(このマシン, iPhone 16 Pro / iOS 18.1 simulator):**
  - `@expo/fingerprint` 指紋生成、`native-build-needed.sh` の skip/needed 判定 + キャッシュ更新(build 後 `skip` に変わることを確認)。
  - **ローカルビルド `expo run:ios`(無料)で dev-client(`com.narikei74.turilog.dev`)が simulator に install** されること(brew cocoapods 対処込み)。
  - dev-client → Metro 接続(`exp+turilog://…`)→ JS バンドル → **釣りログのログイン画面が描画**されること。
  - **Maestro がシミュレータを操作**(tapOn / extendedWaitUntil / runFlow-when / takeScreenshot)し、確認ダイアログ通過・dev メニュー閉じ・スクショ取得まで動作。
  - スクショ取得(`simctl io screenshot` / Maestro `takeScreenshot`)。
- ⛔ **未検証(dev API トークン待ち):** `turilog://dev-auth?token=` による認証注入の実挙動と、ログイン後のタブ巡回スクショ。**`TSURILOG_DEV_API_TOKEN`(dev 環境の api_token)が入手でき次第、qa.yaml を実走して本ファイルに追記する。**
- ⛔ 未検証: `eas build` / `eas build:run`(install)経路 — ローカルビルドが使えるため当面不要。
