#!/usr/bin/env bash
#
# php-lint.sh — PHP 8.4 構文チェッカー(tsurilog-backend 用)
#
# backend のランタイムは PHP 8.4(Laravel 12)。ローカル機の `php` が
# 古い / 入っていないケースに左右されないよう、Docker の `php:8.4-cli`
# イメージで `php -l` を実行して構文を機械検証する。
#
# 使い方:
#   php-lint.sh <file1.php> [file2.php ...]   ← 指定ファイルを lint
#   php-lint.sh --hook                         ← Claude Code hook 用(stdin JSON)
#
# 終了コード:
#   0 = OK(または対象外でスキップ)
#   1 = 環境エラー(Docker 不在等。hook を止めないよう注意して扱う)
#   2 = PHP 構文エラー検出(Claude Code hook の blocking 用)
#
# 注: 対象は tsurilog-backend 配下の .php のみ。native(TS)は native-check.sh。

set -uo pipefail

DOCKER_IMAGE="php:8.4-cli"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"

err() { printf '%s\n' "$*" >&2; }

emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source php-lint.sh --event "$1" --outcome "$2" --details "${3:-{\}}" || true
}

is_backend_php() {
    # tsurilog-backend 配下の .php だけを対象にする
    [[ "$1" == *.php ]] || return 1
    [[ "$1" == *"/tsurilog-backend/"* ]] || return 1
    return 0
}

ensure_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        err "[php-lint] docker が見つかりません。lint をスキップします。"
        return 1
    fi
    if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
        err "[php-lint] $DOCKER_IMAGE を pull します(初回のみ)..."
        docker pull "$DOCKER_IMAGE" >/dev/null 2>&1 || { err "[php-lint] pull 失敗。スキップ。"; return 1; }
    fi
    return 0
}

lint_one() {
    local abs_path="$1"
    [[ -f "$abs_path" ]] || { err "[php-lint] ファイルなし: $abs_path"; return 0; }
    local dir base out
    dir="$(cd "$(dirname "$abs_path")" && pwd)"
    base="$(basename "$abs_path")"
    if out=$(docker run --rm -v "$dir":/w -w /w "$DOCKER_IMAGE" php -l "$base" 2>&1); then
        return 0
    else
        err "❌ PHP 8.4 構文エラー: $abs_path"
        err "$out"
        return 2
    fi
}

main_files() {
    ensure_docker || exit 1
    local rc=0
    for f in "$@"; do
        is_backend_php "$f" || continue
        lint_one "$f" || rc=2
    done
    exit $rc
}

main_hook() {
    local fp="" payload
    payload=$(cat)
    if command -v jq >/dev/null 2>&1; then
        fp=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
    else
        fp=$(printf '%s' "$payload" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    fi

    [[ -n "$fp" ]] || exit 0
    is_backend_php "$fp" || exit 0

    if ! ensure_docker; then
        # Docker 無しなら blocking しない(silent skip)
        exit 0
    fi

    local fp_json
    fp_json=$(printf '%s' "$fp" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$fp")
    if lint_one "$fp"; then
        emit hook_lint pass "{\"file\":$fp_json}"
        exit 0
    else
        emit hook_lint fail "{\"file\":$fp_json}"
        exit 2
    fi
}

[[ $# -eq 0 ]] && { err "usage: php-lint.sh <file.php> [...] | --hook"; exit 1; }
case "${1:-}" in
    --hook) shift; main_hook "$@" ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) main_files "$@" ;;
esac
