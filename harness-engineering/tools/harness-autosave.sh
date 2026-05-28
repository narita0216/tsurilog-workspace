#!/usr/bin/env bash
#
# harness-autosave.sh — workspace(メタリポ)の変更を自動 commit & push する
#
# Stop フック(Claude のターン終了時)から呼ばれる。workspace に未コミットの
# 変更があれば commit し、未 push のコミットがあれば push する。
# Claude が学んだこと・ハーネス更新(CLAUDE.md / ADR / findings / tools /
# effectiveness ログ)を、人手を介さず master に蓄積し GitHub に反映する。
#
# 設計方針(ADR-0005):
#   - 対象は **workspace メタリポのみ**。サブリポ(native/backend)は .gitignore
#     済みなので `git add -A` でも混入しない。さらに remote 名で二重ガード。
#   - **ターンを止めない**: いかなる失敗でも exit 0(commit/push 失敗は次回拾う)。
#   - **ノイズ抑制**: 変更が無ければ何もしない(空コミットを作らない)。
#   - **非対話**: SSH passphrase 等で固まらないよう BatchMode + timeout。
#   - **無効化**: HARNESS_AUTOSAVE_DISABLE=1 で完全停止。
#   - rebase/merge 進行中はスキップ。

set -uo pipefail

# --- disable switch ---
[[ "${HARNESS_AUTOSAVE_DISABLE:-0}" == "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"

emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source harness-autosave.sh --event autosave --outcome "$1" --details "${2:-{\}}" || true
}

cd "$WORKSPACE_ROOT" 2>/dev/null || exit 0

# git リポでなければ何もしない
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# 二重ガード: remote が workspace メタリポでなければ触らない(コードリポ保護)
remote_url="$(git remote get-url origin 2>/dev/null || echo "")"
case "$remote_url" in
    *tsurilog-workspace*) : ;;
    *) emit skip_wrong_repo; exit 0 ;;
esac

# rebase / merge / cherry-pick 進行中はスキップ
gitdir="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
if [[ -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" \
      || -f "$gitdir/MERGE_HEAD" || -f "$gitdir/CHERRY_PICK_HEAD" ]]; then
    emit skip_inprogress
    exit 0
fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

# --- 1) 変更があれば commit ---
committed=0
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    git add -A 2>/dev/null || { emit add_failed; exit 0; }
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    host="$(hostname -s 2>/dev/null || echo unknown)"
    if git commit -q -m "chore(harness): autosave ${ts} [${host}]" 2>/dev/null; then
        committed=1
    fi
fi

# --- 2) 未 push があれば push(非対話・timeout 付き) ---
ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo "?")"
if [[ "$ahead" == "?" ]]; then
    # upstream 未設定。一度だけ -u で設定を試みる(失敗は許容)
    push_cmd=(git push -u origin "$branch")
elif [[ "$ahead" -gt 0 ]]; then
    push_cmd=(git push)
else
    # push 不要。commit だけしていれば記録して終了
    [[ "$committed" == "1" ]] && emit committed_nopush || emit noop
    exit 0
fi

# 非対話設定 + timeout(あれば)
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"
TIMEOUT_BIN=""
command -v timeout  >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="gtimeout"

if [[ -n "$TIMEOUT_BIN" ]]; then
    if "$TIMEOUT_BIN" 30 "${push_cmd[@]}" >/dev/null 2>&1; then
        emit pushed
    else
        emit push_failed   # オフライン等。commit はローカルに残り次回拾う
    fi
else
    if "${push_cmd[@]}" >/dev/null 2>&1; then
        emit pushed
    else
        emit push_failed
    fi
fi

exit 0
