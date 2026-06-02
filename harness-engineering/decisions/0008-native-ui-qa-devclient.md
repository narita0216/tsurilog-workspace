# ADR-0008: native の UI 自動QA(dev-client + Maestro + スクショPR添付)

- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** narikei_74
- **Tags:** harness, native, qa, e2e, screenshots, eas, telemetry

## Context

釣りログ native はスマホアプリ(Expo / dev-client 前提)で、**AI が自分の実装結果を画面で確認する術が無い**。型・lint が通っても画面が壊れていることは検知できず(既知リスク #3: native テスト実質ゼロ)、人間が毎回手で動作確認していてレビューコストが高い。

やりたいこと:
1. AI が「実装に関わる画面」をシミュレータで通り、スクショを撮る(動線を通る = 実質 E2E)。
2. スクショを PR に添付し、人間レビューを「読むだけ」に軽くする。
3. dev-client(ネイティブコード含む)前提の確認を AI ができる。**ただし EAS の無料ビルド枠は限られる**ため、build 回数は最小化する。

制約として効く事実(調査で確認):
- 認証は Apple/Google のネイティブサインインモーダル。トークンは `expo-secure-store` の `"accessToken"` キー(`hooks/use-auth.ts`)。**シミュレータ+自動操作でネイティブサインインは安定通過できない。**
- dev variant の bundle id は `com.narikei74.turilog.dev`、scheme は `turilog`。`expo-linking` は依存にあるが deep-link はほぼ未活用。
- `eas.json` の `development` は `distribution: internal`(=実機 ipa)。**シミュレータ用 `.app` には `ios.simulator: true` が要る。**
- `@expo/fingerprint`(v0.15.5)が native に同梱。ネイティブ指紋を hash 化できる。
- `eas build`(枠を消費)と `eas build:run`(既存成果物を DL して install。枠を消費しない)は別物。

## Options

### build 要否の判定方法
- **A. ネイティブ指紋(@expo/fingerprint)で判定** — 指紋が変われば build、同じなら Metro 配信。
  - Pros: ネイティブ依存の変化を漏れなく捉える(package.json ネイティブ依存 / app.json / app.config.ts / eas.json / plist / expo-build-properties / SDK)。Expo 公式の指紋ロジックそのもの。
  - Cons: 「最後に install した dev-client の指紋」を別途キャッシュする必要。
- **B. git diff のパスをヒューリスティック判定**(例: `app/**` は JS、`package.json` は native)
  - Pros: 単純。
  - Cons: 取りこぼす(例: transitive なネイティブ依存、build-properties)。脆い。

### 認証回避
- **C. dev-client 限定の deep-link トークン注入**(`turilog://dev-auth?token=`)
  - Pros: 安定。Maestro の `openLink` 一発。production では無効化できる。
  - Cons: native に小さなハンドラ追加が要る。
- **D. Maestro でネイティブサインインを自動操作** — シミュレータの Apple ID 状態に依存し不安定。却下。

### スクショの PR 添付
- **E. PR ブランチに `qa-artifacts/` として commit + raw URL 埋め込み** — gh/MCP で完結。squash で消える。
- **F. GitHub user-attachments API** — gh/MCP から安定して扱えない。却下。

## Decision

**A + C + E を採用する。**

1. **build 要否 = ネイティブ指紋(A)。** `native-build-needed.sh` が `@expo/fingerprint` で現在の指紋を生成し、「最後に `build:run` でシミュレータに入れた dev-client の指紋」(`assessment/.native-fingerprint-<variant>`、gitignore = マシン依存ローカル状態)と比較。一致なら `skip`(Metro 配信)、相違/無しなら `needed`。

2. **`eas build` はハーネスから自走させない。** `native-qa.sh` は build が必要と判定したら**案内して停止**(exit 20)。実ビルドはユーザーの明示実行のみ(`.claude/settings.json` でも `eas build`/`eas submit` は deny)。install は `eas build:run -p ios --latest`(枠を消費しない)で行い、成功時に指紋キャッシュを更新する。

3. **認証回避 = dev-client 限定 deep-link 注入(C)。** native 側に `__DEV__ && variant==='development'` ガードで `turilog://dev-auth?token=` ハンドラを実装(別 PR)。**production ビルドでは完全に無効。**

4. **QA 本体 = Maestro(iOS シミュレータ)。** `native-qa.sh` が Metro 起動 → dev-client を Metro に接続 → deep-link 認証注入 → Maestro フロー(`.maestro/`)実行 → `takeScreenshot`。

5. **スクショ添付 = PR ブランチ commit(E)。** native の feature ブランチに `qa-artifacts/<ts>/*.png` を commit し PR 本文に `…?raw=true` で埋め込む。

6. **テレメトリ:** 各ツールは `effectiveness-log.sh` で build要否(`skip`/`needed`)・QA結果(`ok`/`fail`)を emit。

## Consequences
- **得るもの:** AI が画面の証跡を出せる(実質 E2E)。人間レビューが軽くなる。**JS/TS だけの変更で EAS build が走らない**ことを指紋で保証 = 無料枠温存。
- **失うもの:** native に dev-auth deep-link ハンドラと `.maestro/` を保守する責務。Maestro のセレクタ(testID)を実装に合わせ続ける必要。
- **新たに発生する作業:** 初回は指紋キャッシュが無く必ず `needed` → 1 度 build + `install` が要る。Maestro フローの testID チューニングは初回実行時に行い `findings/` に記録。
- **後戻り可能性:** reversible(ツール削除 + native の dev ハンドラ撤去で戻せる。dev ハンドラは production 無効なので残っても無害)。
- **セキュリティ:** dev-auth は dev variant + `__DEV__` 限定。`TSURILOG_DEV_API_TOKEN` は dev API のテスト用トークンを環境変数で渡し、コード/リポにハードコードしない(リスク #4b と同じ方針)。

## Related
- ツール: `tools/native-qa.sh` / `tools/native-build-needed.sh` / `tools/maestro/flow-template.yaml`
- スキル: `/native-qa`(`.claude/commands/native-qa.md`)、SKILL_INDEX
- finding: `findings/2026-06-02-native-devclient-qa-maestro.md`(技術メモ・ハマりどころ)
- native PR(別リポ): dev-auth deep-link / `eas.json` simulator / `.maestro/`
- 既知リスク #3(native テストゼロ)の緩和。CLAUDE.md §8.3
- 関連: ADR-0004(品質ゲートと hooks)
