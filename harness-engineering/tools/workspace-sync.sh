#!/usr/bin/env bash
#
# workspace-sync.sh — 2 サブリポの git 状態を一望する pre-flight
#
# 釣りログのワークスペースは tsurilog-native と tsurilog-backend を兄弟配置
# する作業ディレクトリ。タスク着手前に「両リポの現在ブランチ・未コミット
# 変更・develop からの遅れ」を把握しておくと、片側だけ古いまま実装して
# しまう事故を防げる。
#
# 使い方:
#   workspace-sync.sh check    … SessionStart hook 用。要注意点があれば通知、
#                                 健全なら 1 行サマリ
#   workspace-sync.sh status   … 詳細表示
#
# 注: fetch はしない(オフライン/権限の都合)。ローカルの追跡情報のみで判定。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"

REPOS=("tsurilog-native" "tsurilog-backend")
MODE="${1:-check}"

emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source workspace-sync.sh --event "$MODE" --outcome "$1" --details "${2:-{\}}" || true
}

report_repo() {
    local name="$1" dir="$WORKSPACE_ROOT/$1"
    [[ -d "$dir/.git" ]] || { echo "  $name: (git リポジトリなし)"; return 0; }
    local branch dirty ahead
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    local flags=""
    [[ "$dirty" != "0" ]] && flags+=" 📝未コミット${dirty}件"
    case "$branch" in
        main|master) flags+=" ⚠️mainで作業中" ;;
    esac
    echo "  $name: ${branch}${flags}"
}

if [[ "$MODE" == "check" ]]; then
    notes=0
    out=""
    for r in "${REPOS[@]}"; do
        line=$(report_repo "$r")
        out+="$line"$'\n'
        [[ "$line" == *"⚠️"* || "$line" == *"📝"* ]] && notes=$((notes+1))
    done
    if [[ $notes -gt 0 ]]; then
        echo "[workspace-sync] 着手前チェック:"
        printf '%s' "$out"
        emit notes
    else
        echo "[workspace-sync] 両リポともクリーン。"
        emit clean
    fi
    exit 0
fi

# status (詳細)
echo "🎣 tsurilog workspace — git 状態"
echo "================================"
for r in "${REPOS[@]}"; do
    report_repo "$r"
done
emit ok
exit 0
