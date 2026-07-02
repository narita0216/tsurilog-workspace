# native-qa のローカル既定漏れ と 起動時 QA の不安定要因（2026-07-02）

## 何が起きたか
1.1.5 の UI を `/native-qa`（シミュレータ + Maestro）で検証しようとして連続で失敗。原因は**プロダクトのバグではなく、QA ハーネスの取りこぼしと環境要因**だった。

## 判明した事実 / 修正（harness）
- **§8.0（AIはローカルで検証）なのに、native-qa.sh がローカルAPIを既定にしていなかった。**
  - `EXPO_PUBLIC_API_DOMAIN` は「呼び出し元の env から継承」する設計で、未指定だと安定しない。→ **未指定時 `http://localhost:8080`（ローカルDocker）を既定にする**よう修正。
- **dev-auth はトークンを注入しても `EXPO_PUBLIC_DEV_AUTH_REDIRECT` が無いと画面遷移せずログイン画面に留まる。**
  - これで「認証したのにログイン画面のまま」に見えて何度もハマった。→ **未指定時 `/(tabs)`（ホーム）を既定**にするよう修正。別画面を撮るフローは呼び出し元で上書き（例 `/analysis`）。
- `TSURILOG_DEV_API_TOKEN` は名前が "DEV" だが**実体は「検証先backendで有効な api_token」**。ローカルDockerで発行したトークンでよい（tinker で作成）。dev API 必須ではない。precond 文言も修正。

## 環境要因（プロダクト問題ではない）
- **シミュレータが idle でロック画面**になり `simctl openurl` がアプリを前面化できない。`simctl` に unlock は無い → `osascript`で Simulator を activate + Cmd+Shift+H で解除できた。
- **DEV レビュー誘導のデバッグAlert（`maybePromptReview`・本番非表示）が起動直後に遅れて出る**。出現タイミングがラン毎に非決定的（レビュー誘導の内部状態が蓄積）。→ フローは「settle待ち→OKを日和見タップ×2」で出ても出なくても通す形にする。
- **無データQAユーザーのホームが描画しきれない**（pins/records/dashboard のシードが無いと空/ロード）。→ ホーム到達を assert するなら**ローカルDBにシードが要る**。

## 教訓 / TODO
- native-qa は**ローカルDockerが既定**に直った。以後は `TSURILOG_DEV_API_TOKEN=<ローカルtoken>` だけ渡せばよい（API_DOMAIN/REDIRECT は既定でホーム）。
- 起動時に出る DEV Alert はヘッドレスQAの障害物。QA用に**レビュー誘導を抑止するフラグ**（例 `EXPO_PUBLIC_QA=1` で maybePromptReview を skip）を native に入れると安定する（次の native 改善候補）。
- 空ユーザーでも撮れるよう、QA前に**ローカルDBへ最小シード**（pin数件・record数件）する tinker を native-qa に用意すると、ホーム/図鑑まで安定して撮れる。
