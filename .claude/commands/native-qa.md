---
description: native dev-client を iOS シミュレータで動かし画面遷移→スクショ撮影(実質E2E)。build要否は指紋で自動判定し EAS 無料枠を温存
argument-hint: "(任意) run | install | check  [--flow <path>] [--no-build] [--dry-run]"
---

`tsurilog-native` の dev-client を iOS シミュレータで起動し、**実装に関わる画面を Maestro で通ってスクショを撮る**。スクショは実質 E2E の証跡として PR に添付し、人間レビューのコストを下げる(ADR-0008)。

> **EAS 無料枠の鉄則:** `eas build`(ビルド枠を消費)は **このフローからは絶対に自走させない**。build が必要と判定されたら案内して停止する。JS/TS だけの変更は build 不要 = Metro 配信で反映。

## 0. 前提

- native で `npm install` 済み。
- iOS シミュレータが起動済み(`xcrun simctl boot <udid>` など)。
- dev-client(`com.narikei74.turilog.dev`)がシミュレータに install 済み。未 install または指紋相違なら `install` が要る(下記 2)。
- `TSURILOG_DEV_API_TOKEN` … dev API(`https://dev.api.tsuri-log.com`)で発行済みのテスト用 api_token。**Apple/Google ネイティブサインインを回避する dev 認証注入に必須**。
- native 側に dev-auth deep-link ハンドラ(`turilog://dev-auth?token=`)と `.maestro/` フローが入っていること(対の native PR)。
- `maestro` CLI(`curl -fsSL https://get.maestro.mobile.dev | bash`)。

## 1. build 要否だけ見る

```bash
harness-engineering/tools/native-qa.sh check
```

`skip`(指紋一致 = build 不要) / `needed`(初回 or ネイティブ依存変更 = build 必要)。判定本体は `native-build-needed.sh`(`@expo/fingerprint`)。

## 2. ビルドが必要なとき(needed)

`eas build` は **手動で承認・実行**する(枠を消費するため):

```bash
# 1) ビルド(枠を消費)— 明示実行のみ。eas.json の development に "ios": {"simulator": true} が必要
(cd tsurilog-native && eas build -p ios --profile development)

# 2) install + 指紋キャッシュ更新(枠は消費しない build:run)
harness-engineering/tools/native-qa.sh install
```

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
