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
- 解決: dev-client 限定で `turilog://dev-auth?token=<api_token>` を受けて `setItemAsync("accessToken", token)` + `useAppStore.setAccessToken` → タブへ replace。`__DEV__ && EXPO_PUBLIC_APP_VARIANT==='development'` ガード。**production では完全に無効。**
- ★**実装は `_layout` の hook ではなく expo-router の実ルート `app/dev-auth.tsx` にする。**
  hook(`Linking.useURL`)方式だと **expo-router が `turilog://dev-auth` を「ルート遷移」として横取りし、該当ルートが無いので "Unmatched Route" 画面**になり hook の `router.replace` に勝てなかった(2026-06-02 実機で遭遇)。実ルートにすれば正規遷移し、その画面で token 処理 → `/(tabs)` へ replace できる。
- ★**`EXPO_PUBLIC_APP_VARIANT=development` が必須。** EAS development profile は eas.json で設定済みだが、**ローカル `expo run:ios` / `expo start` は .env に無いと未設定**になり dev-auth が無効化される。→ `native-qa.sh` が build / Metro 起動時に必ず `EXPO_PUBLIC_APP_VARIANT=development` を設定する。
- Maestro 側は `openLink: "turilog://dev-auth?token=${DEV_API_TOKEN}"`。トークンは `maestro -e DEV_API_TOKEN=...` で注入(ハードコードしない)。**⚠️ flow の `env:` に `DEV_API_TOKEN: ""` のデフォルトを置くと `-e` 値を上書きして空になる** → デフォルトを置かない。
- openLink/openurl でも「"釣りログ" で開きますか?」確認ダイアログが出るので「開く」をタップする。

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

- **Maestro の testID:** native に testID が無い。タブの**テキストラベルは accessibility に露出せず `tapOn:text` で取れなかった** → 下タブを**座標タップ**(4 分割: 12.5/37.5/62.5/87.5%, y=95%)。安定運用には testID を足すのが望ましい。
- **トークン無しで E2E を回す方法(ローカル backend):** dev API のトークンが手元に無くても、**ローカル backend(`docker-compose-local.yml`, 既に :8080 稼働)にテストユーザーを作り**(`artisan tinker` で `User::firstOrCreate(['username'=>'qa_tester'],['api_token'=>'<uuid>','nickname'=>'QA Tester'])`)、アプリの `.env` を `EXPO_PUBLIC_API_DOMAIN=http://localhost:8080` に向ければ自走で認証フローを実証できる。simulator → Mac localhost は到達可。ATS は dev ビルドの `NSAllowsLocalNetworking=true` で HTTP 許可。**`.env` は gitignore 済み**なので戻し忘れてもコミットされないが、検証後は `https://dev.api.tsuri-log.com` に戻すこと。
- **Metro の起動完了待ち:** `native-qa.sh` は `http://localhost:8081/status` を polling。port 競合時は `METRO_PORT`。
- **ローカルビルドは無料・自走可:** `native-qa.sh build`(= `expo run:ios`)。`eas build`(枠消費)は deny + 自走禁止。
- **スクショ PR 添付:** native feature ブランチに `qa-artifacts/<ts>/` を commit → PR 本文に `https://github.com/<owner>/tsurilog-native/blob/<branch>/qa-artifacts/<ts>/xxx.png?raw=true`。squash merge 前提で履歴を汚さない。
- **`expo run:ios` の最終ステップ(`osascript` で Simulator 窓を前面化)は AppleScript 自動化権限が無い env で失敗するが、`.app` の install は完了している**(無視してよい)。アプリ起動は `xcrun simctl launch` で代替。

## 6. 検証済み / 未検証(2026-06-02 実走で更新)

- ✅ **全経路 検証済み(このマシン, iPhone 16 Pro / iOS 18.1 simulator + ローカル backend):**
  - `@expo/fingerprint` 指紋生成、`native-build-needed.sh` の skip/needed 判定 + キャッシュ更新(build 後 `skip` に変わることを確認)。
  - **ローカルビルド `expo run:ios`(無料)で dev-client(`com.narikei74.turilog.dev`)が simulator に install**(brew cocoapods 対処込み)。
  - dev-client → Metro 接続(`exp+turilog://…`)→ JS バンドル → ログイン画面描画。
  - **dev-auth ルート(`app/dev-auth.tsx`)で `turilog://dev-auth?token=` による認証注入 → ホーム(「QA Tester さん」)が localhost backend のデータで描画**されること。
  - **Maestro による認証済みタブ巡回**(ホーム/釣行記録「記録がありません」/マップ/プロフィール)とスクショ取得。
  - `effectiveness-log` への emit。
- ⛔ 未検証: `eas build` / `eas build:run`(install)経路 — ローカルビルドが使えるため当面不要。
- 🔭 改善余地: タブの testID 付与(座標タップ依存の解消)、マップ/プロフィールのオンボーディング コーチマークをまたぐ遷移、analysis API 遅延(~10-20s)の待ち最適化。
