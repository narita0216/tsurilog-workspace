# GitHub MCP トークンが別アカウント(narikei-74)で、narita0216 リポへの PR 作成が 404

- **Date:** 2026-05-29
- **Tags:** github, mcp, auth, workflow
- **関連:** CLAUDE.md §7 リスク#6・§8.6

## 何が起きたか

native の作業ブランチ `feature/ai-strategy-mock` を push 後、`mcp__github__create_pull_request`
(owner=narita0216 / repo=tsurilog-native / base=develop)で **404 Not Found**。
`mcp__github__get_me` で確認すると MCP トークンの認証ユーザーは **`narikei-74`**。
リポ所有者は **`narita0216`** で別アカウントのため、PR API 権限が無く 404 になる。

- ローカル git の push は SSH host エイリアス `github-narita0216`(narita0216 の鍵)経由で**成功**する。
- つまり「push はできるが MCP 経由の PR 作成はできない」非対称な状態。
- `gh` CLI は未インストール(`command not found: gh`)。

## 回避策(現状)

1. **ブランチを push まで実施** → ユーザーがブラウザで PR を作成。
   compare URL: `https://github.com/<owner>/<repo>/compare/develop...<branch>?expand=1`
   (例: `https://github.com/narita0216/tsurilog-native/compare/develop...feature/ai-strategy-mock?expand=1`)
2. PR 本文案は Claude が用意し、ユーザーが貼り付け。

## 恒久対応の候補(要判断)

- A. MCP のトークンを **narita0216 の PAT**(repo スコープ)に差し替える(`.mcp.json` / 環境変数)。
- B. `gh` をインストールし `gh auth login` を narita0216 で済ませてフォールバックに使う。
- C. backend(reomin 所有)も含めると、MCP トークン 1 つで両リポ PR を作るのは困難 → リポごとに経路を分ける運用を明記。

## メモ

- `git user` は `narikei_74`、SSH は `github-narita0216`、MCP は `narikei-74`、リポは `narita0216` と
  **4 つの識別子が混在**。新規セッションで PR を自動作成しようとすると毎回詰まるため、本 finding を参照。
