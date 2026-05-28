# ADR-0005: workspace メタリポは Stop フックで自動 commit & push

- **Status:** Accepted
- **Date:** 2026-05-28
- **Deciders:** narita0216
- **Tags:** harness, automation, git, autonomy

## Context

workspace(`narita0216/tsurilog-workspace`、branch `master`)は **100% AI 管理のメタリポ**で、ハーネス・ドキュメント・ADR・findings・effectiveness ログを置く(コードは含まない / サブリポは .gitignore)。本番デプロイを持たないため、コードリポ(`main` 保護・PR 必須)とは運用が異なる。

Claude が学んだこと・ハーネス改善を人手のコミットに依存すると、反映漏れ・取りこぼしが起きる。「Claude が更新したら自動で master に commit & push される」状態にしたい。

注意点:
- **メモリ**(`~/.claude*/.../memory/`)は workspace の外にあり git 対象外。学びをリポに残すには `CLAUDE.md` / `findings/` / ADR に書き出す必要がある(本 ADR の対象は「リポ内の変更を自動で push する」部分)。
- 当初 `settings.json` が `git push origin master` / `git checkout master` を deny しており、workspace 自身の master への push をブロックしていた(コードリポ用 deny の流用バグ)→ 本 ADR で修正。

## Options

### Option A: Stop フックで完全自動(採用)
- ターン終了ごとに `harness-autosave.sh` が走り、変更があれば `add -A → commit → push`。
- **Pros:** 文字通り自動。反映漏れゼロ。メタリポなので「未完成コード混入」リスクが小さい。
- **Cons:** コミットがやや多くなる(特に effectiveness ログが毎ターン変わる)。未確定の編集も push し得る。オフライン時は push 失敗(commit はローカルに残り次回拾う)。

### Option B: 行動規約のみ(airtrunk 流)
- CLAUDE.md に「ターン内で commit & push してよい」と明記し、Claude が判断して実行。
- **Pros:** 意味あるコミットメッセージ。中途半端な push を避けられる。
- **Cons:** 「自動」ではなく Claude の判断依存(忘れ得る)。

### Option C: ハイブリッド(規約 + Stop フックのセーフティネット)
- 通常は Claude が commit、Stop フックが未 push 分を拾う。
- **Cons:** 実装が複雑。

## Decision

**Option A を採用する。** Stop フック → `harness-engineering/tools/harness-autosave.sh` で、workspace の変更を自動 commit & push する。

ガード:
- 対象は **workspace メタリポのみ**(remote 名 `*tsurilog-workspace*` を確認。コードリポでは何もしない)。
- **ターンを止めない**(全失敗で exit 0)。push 失敗時は commit をローカルに残し次回拾う。
- 空コミットは作らない。rebase/merge 進行中はスキップ。
- 非対話(`GIT_TERMINAL_PROMPT=0` + SSH BatchMode + timeout)で固まらない。
- `HARNESS_AUTOSAVE_DISABLE=1` で無効化可能。

あわせて `settings.json` の deny を修正:`git push origin master` / `git checkout master` を**解除**(workspace に必要)、コードリポ保護用に `git push origin main` / `git push origin develop` / `git checkout main` を**残置**。

## Consequences
- **得るもの:** ハーネス更新・学び(`findings`/ADR/`CLAUDE.md` に書いたもの)が自動で GitHub に蓄積。
- **失うもの:** autosave コミットのメッセージは機械的(意味を持たせたい時は手動 commit)。
- **テレメトリの扱い(検証で判明):** effectiveness の `events-*.jsonl` は **毎ターン変わる**ため、追跡すると autosave が「テレメトリだけで毎ターンコミット」する tail-chasing が発生する。よって **`.gitignore` で除外**し、autosave は **意味あるハーネス/ドキュメント変更があった時だけ**コミットするようにした。テレメトリはローカル蓄積(self-review 用)。複数マシンで共有したくなれば除外を外す。
- **新たに発生する作業:** 設定変更後は **Claude Code の再起動**でフック(Stop / deny)有効化。
- **後戻り可能性:** reversible(`settings.json` の Stop フックを外す / `HARNESS_AUTOSAVE_DISABLE=1`)。
- **注意:** メモリは push されない。重要な学びは findings/CLAUDE.md/ADR に書き出すこと(CLAUDE.md §8.5)。

## Related
- ツール: `harness-engineering/tools/harness-autosave.sh`
- 設定: `.claude/settings.json`(Stop フック / deny 修正)
- ADR-0004(hooks 全体)
- CLAUDE.md §1 / §6.1 / §8.5 / §8.7
