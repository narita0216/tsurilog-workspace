#!/usr/bin/env bash
#
# native-check.sh — tsurilog-native の品質ゲート(ESLint + tsc + Prettier)
#
# Expo SDK 54 / React 19 / TypeScript。package.json の script に従う:
#   - `npm run lint`   = `expo lint && tsc --noEmit`(ESLint + 型チェック)
#   - `npm run format` = `prettier . --write`(整形)
#
# 使い方:
#   native-check.sh             … lint(= expo lint + tsc --noEmit)
#   native-check.sh format      … prettier で整形(書き込みあり)
#   native-check.sh format:check… prettier --check(非破壊)
#   native-check.sh types       … tsc --noEmit のみ
#
# 前提: native で `npm install` 済み(node_modules が存在)。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
NATIVE="${TSURILOG_NATIVE_DIR:-$WORKSPACE_ROOT/tsurilog-native}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"

err() { printf '%s\n' "$*" >&2; }
emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source native-check.sh --event "$1" --outcome "$2" --details "${3:-{\}}" || true
}

[[ -d "$NATIVE" ]] || { err "[native-check] native ディレクトリなし: $NATIVE"; exit 1; }
command -v npm >/dev/null 2>&1 || { err "[native-check] npm が必要です(Node.js v20+)。"; exit 1; }
if [[ ! -d "$NATIVE/node_modules" ]]; then
    err "[native-check] node_modules がありません。次を実行してください:"
    err "    (cd $NATIVE && npm install)"
    exit 1
fi

nrun() { ( cd "$NATIVE" && "$@" ); }

cmd="${1:-lint}"; shift || true
rc=0
case "$cmd" in
    lint)         nrun npm run lint || rc=$? ;;
    types)        nrun npx tsc --noEmit || rc=$? ;;
    format)       nrun npm run format || rc=$? ;;
    format:check) nrun npx prettier . --check || rc=$? ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) err "unknown subcommand: $cmd"; sed -n '2,18p' "$0"; exit 1 ;;
esac

[[ $rc -eq 0 ]] && emit "$cmd" pass || emit "$cmd" fail
exit $rc
