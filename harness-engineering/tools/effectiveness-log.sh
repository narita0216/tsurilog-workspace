#!/usr/bin/env bash
#
# effectiveness-log.sh — ハーネスツールの実行結果を JSONL に追記する thin logger
#
# 目的:
#   ハーネス自身の使用状況・hook の reject 頻度・skill 死蔵率を観測し、
#   Claude が `/effectiveness-review` 相当の振り返りで読んで harness を自律改善
#   するための材料を残す。設計背景は ADR-0004 を参照。
#
# 使い方:
#   effectiveness-log.sh emit \
#     --source <tool-name> \
#     --event <event-name> \
#     --outcome <outcome> \
#     [--details '<json-string>']
#
#   # 例:
#   effectiveness-log.sh emit --source contract-check.sh --event check --outcome drift
#   effectiveness-log.sh emit --source php-lint.sh --event hook_lint --outcome fail \
#       --details '{"file":"app/Http/Controllers/Api/LogCreateController.php"}'
#
# 書き込み先:
#   <workspace>/harness-engineering/assessment/effectiveness/events-<hostname>.jsonl
#   (マシン別ファイルで複数マシン同時編集の conflict を回避)
#
# 副作用:
#   - 書き込み失敗時も exit 0(計測のために本来の処理を止めない)
#   - $EFFECTIVENESS_LOG_DISABLE=1 で完全無効化

set -uo pipefail

# スクリプト位置から workspace root を導出(ポータブル)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
LOG_DIR="$WORKSPACE_ROOT/harness-engineering/assessment/effectiveness"

if [[ "${EFFECTIVENESS_LOG_DISABLE:-0}" == "1" ]]; then
    exit 0
fi

usage() {
    cat <<EOF
Usage: effectiveness-log.sh emit --source <name> --event <name> --outcome <name> [--details '<json>']
EOF
}

emit() {
    local source="" event="" outcome="" details="{}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source)  source="$2"; shift 2 ;;
            --event)   event="$2"; shift 2 ;;
            --outcome) outcome="$2"; shift 2 ;;
            --details) details="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$source" || -z "$event" || -z "$outcome" ]]; then
        return 0
    fi

    if ! printf '%s' "$details" | python3 -c 'import sys, json; json.loads(sys.stdin.read())' >/dev/null 2>&1; then
        details="{}"
    fi

    local ts host log_file line
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    host=$(hostname -s 2>/dev/null || echo "unknown")
    log_file="$LOG_DIR/events-${host}.jsonl"

    mkdir -p "$LOG_DIR" 2>/dev/null || return 0

    line=$(python3 -c '
import sys, json
ts, host, source, event, outcome, details = sys.argv[1:7]
try:
    d = json.loads(details)
except Exception:
    d = {}
print(json.dumps({
    "ts": ts, "host": host, "source": source,
    "event": event, "outcome": outcome, "details": d,
}, ensure_ascii=False))
' "$ts" "$host" "$source" "$event" "$outcome" "$details" 2>/dev/null) || return 0

    if command -v flock >/dev/null 2>&1; then
        ( flock -x 200; printf '%s\n' "$line" >> "$log_file" ) 200>"$log_file.lock" 2>/dev/null
    else
        printf '%s\n' "$line" >> "$log_file" 2>/dev/null
    fi
    return 0
}

if [[ $# -eq 0 ]]; then usage; exit 0; fi
sub="$1"; shift
case "$sub" in
    emit) emit "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 0 ;;
esac
