---
description: native dev-client を iOS シミュレータで動かし画面遷移→スクショ撮影(実質E2E)。ローカルビルド(expo run:ios)主体で EAS 無料枠を消費しない。build要否は指紋で自動判定
argument-hint: "(任意) build | run | install | check  [--flow <path>] [--device <udid>] [--no-build] [--dry-run]"
---

`tsurilog-native` の dev-client を iOS シミュレータで起動し、**実装に関わる画面を Maestro で通ってスクショを撮る**。スクショは実質 E2E の証跡として PR に添付し、人間レビューのコストを下げる(ADR-0008)。

> **EAS 無料枠の鉄則:** シミュレータ QA のビルドは **ローカル `npx expo run:ios`(= EAS 枠を消費しない)** を使う(`build` サブコマンド)。`eas build`(枠を消費)はこのフローから実行しない(実機配布のときだけ人間が明示実行)。JS/TS だけの変更は build 不要 = Metro 配信で反映。

## 0. 前提

- native で `npm install` 済み。Xcode + CocoaPods + maestro + JDK(`native-qa.sh` が `brew` の cocoapods/openjdk を自動で拾う)。
- maestro は **`brew install mobile-dev-inc/tap/maestro`**(`brew install maestro` は別物が入るので不可)。
- iOS シミュレータが起動済み(`xcrun simctl boot <udid>` / `open -a Simulator`)。
- dev-client(`com.narikei74.turilog.dev`)が install 済み。未 install/指紋相違なら `build`(下記 2)。
- `TSURILOG_DEV_API_TOKEN` … dev API(`https://dev.api.tsuri-log.com`)発行のテスト用 api_token。**Apple/Google サインインを回避する dev 認証注入に必須**。
- native 側に dev-auth deep-link ハンドラ(`turilog://dev-auth?token=`)と `.maestro/` フローが入っていること(対の native PR)。

## 1. build 要否だけ見る

```bash
harness-engineering/tools/native-qa.sh check
```

`skip`(指紋一致 = build 不要) / `needed`(初回 or ネイティブ依存変更 = build 必要)。判定本体は `native-build-needed.sh`(`@expo/fingerprint`)。

## 2. ビルドが必要なとき(needed)— ★ローカルビルド(無料)

```bash
# ローカル Xcode ビルドで dev-client を simulator に install + 指紋更新。EAS 枠を消費しない。
harness-engineering/tools/native-qa.sh build --device <udid>
# 初回は prebuild + pod install + xcodebuild で ~10-25分。以降 JS 変更では build 不要。
```

> EAS 成果物を使う場合のみ: `eas build -p ios --profile development-simulator`(枠消費・人間が明示実行)→ `native-qa.sh install`(`eas build:run`、枠消費なし)。

## 3. QA 実行(スクショ撮影)

```bash
TSURILOG_DEV_API_TOKEN=<dev token> \
  harness-engineering/tools/native-qa.sh run --flow tsurilog-native/.maestro/<flow>.yaml
```

- 指紋一致なら build せず、Metro 起動 → dev-client 接続 → `turilog://dev-auth` で認証注入 → Maestro フロー → `takeScreenshot`。
- スクショは `tsurilog-native/qa-artifacts/<timestamp>/*.png` に出る。
- `--dry-run` で実行せず経路だけ確認(シミュレータ不要)。`--no-build` で指紋判定を飛ばす(install 済み前提)。

## 4. スクショを PR に添付

撮れた PNG を native の feature ブランチに `qa-artifacts/<ts>/` として commit し、PR 本文に埋め込む:

```markdown
![home](https://github.com/<owner>/tsurilog-native/blob/<branch>/qa-artifacts/<ts>/01-home.png?raw=true)
```

merge 時に squash されれば履歴には残らない。

## 5. フローの編集

`flow-template.yaml`(`harness-engineering/tools/maestro/`)を native の `.maestro/` にコピーし、**今回変更したコードが通る動線**に合わせて遷移・`takeScreenshot` を足す。`testID` は実装に合わせる。

## 6. 注意

- `eas build` / `eas submit` は `.claude/settings.json` で deny。実ビルドはユーザーの明示実行のみ。
- 画面が正しい ≠ lint/型が通る。UI を変えたら可能な範囲でこのフローを通す。通せない場合はその旨を PR に明記(`/native-check` の型・lint と併用)。

## 7. effectiveness emit

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome native-qa
```
