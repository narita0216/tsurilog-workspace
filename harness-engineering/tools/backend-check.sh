#!/usr/bin/env bash
#
# backend-check.sh — tsurilog-backend の品質ゲート(Pint + PHPUnit)
#
# Laravel 12 / PHP 8.4。docker compose の `api` コンテナ内で実行する。
# (compose は backend リポの docker-compose.yml に api/queue/scheduler/db を定義)
#
# 使い方:
#   backend-check.sh              … pint(--test) と test を両方実行
#   backend-check.sh pint         … Laravel Pint のスタイル検査のみ(--test, 非破壊)
#   backend-check.sh pint:fix     … Pint で自動整形(書き込みあり)
#   backend-check.sh test [args]  … php artisan test(args はそのまま渡す)
#
# 前提: backend で `docker compose up -d` 済み、または起動を試みる。
# コンテナが無ければ起動を案内して exit 1。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BACKEND="${TSURILOG_BACKEND_DIR:-$WORKSPACE_ROOT/tsurilog-backend}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"
SERVICE="api"

err() { printf '%s\n' "$*" >&2; }
emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source backend-check.sh --event "$1" --outcome "$2" --details "${3:-{\}}" || true
}

[[ -d "$BACKEND" ]] || { err "[backend-check] backend ディレクトリなし: $BACKEND"; exit 1; }

dc() { ( cd "$BACKEND" && docker compose "$@" ); }

ensure_container() {
    command -v docker >/dev/null 2>&1 || { err "[backend-check] docker が必要です。"; exit 1; }
    if ! dc ps --services --filter "status=running" 2>/dev/null | grep -qx "$SERVICE"; then
        err "[backend-check] '$SERVICE' コンテナが起動していません。次で起動してください:"
        err "    (cd $BACKEND && docker compose up -d)"
        exit 1
    fi
}

run_pint() {
    local mode="$1"  # test | fix
    ensure_container
    if [[ "$mode" == "fix" ]]; then
        dc exec -T "$SERVICE" ./vendor/bin/pint
    else
        dc exec -T "$SERVICE" ./vendor/bin/pint --test
    fi
}

run_test() {
    ensure_container
    dc exec -T "$SERVICE" php artisan test "$@"
}

cmd="${1:-all}"; shift || true
rc=0
case "$cmd" in
    pint)     run_pint test || rc=$? ;;
    pint:fix) run_pint fix  || rc=$? ;;
    test)     run_test "$@" || rc=$? ;;
    all)
        run_pint test || rc=$?
        run_test       || rc=$?
        ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) err "unknown subcommand: $cmd"; sed -n '2,20p' "$0"; exit 1 ;;
esac

[[ $rc -eq 0 ]] && emit "$cmd" pass || emit "$cmd" fail
exit $rc
