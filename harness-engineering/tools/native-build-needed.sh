#!/usr/bin/env bash
#
# native-build-needed.sh — EAS dev-client の再ビルド要否を「ネイティブ指紋」で判定する
#
# 目的:
#   AI(や人間)が native を QA するとき、JS/TS だけの変更なら既存 dev-client +
#   Metro 配信で反映できる。ネイティブ依存(package.json のネイティブモジュール /
#   app.json / app.config.ts / eas.json / plist / expo-build-properties / SDK)が
#   変わったときだけ EAS build が要る。EAS の無料ビルド枠は限られるため、
#   「本当に build が要るか」を @expo/fingerprint で機械判定し、無駄な build を防ぐ。
#   設計背景は ADR-0008 を参照。
#
# 仕組み:
#   @expo/fingerprint(native に同梱)でプロジェクトのネイティブ指紋(hash)を生成し、
#   「最後に simulator に install した dev-client の指紋」(キャッシュ)と比較する。
#     - 一致      → skip  (build 不要。Metro 配信で反映可)
#     - 相違/無し → needed(build 必要。指紋が変わった or 初回)
#
# 使い方:
#   native-build-needed.sh check            # needed|skip を stdout に出す(既定)
#   native-build-needed.sh current          # 現在の指紋 hash を出す
#   native-build-needed.sh update [<hash>]  # キャッシュを更新(build:run 成功後に呼ぶ)
#                                            # hash 省略時は現在の指紋を書き込む
#   native-build-needed.sh diff             # 直近キャッシュとの差分(@expo/fingerprint)
#
# 環境変数:
#   TSURILOG_NATIVE_DIR   native リポのパス(既定: <workspace>/tsurilog-native)
#   QA_VARIANT            指紋キャッシュの variant(既定: development)
#   FINGERPRINT_PLATFORM  指紋対象プラットフォーム(既定: ios)
#
# 終了コード(check):
#   0 = skip(build 不要) / 10 = needed(build 必要) / 1 = エラー
#   ※ stdout には needed|skip の文字列も出すので、どちらで判定してもよい。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
NATIVE="${TSURILOG_NATIVE_DIR:-$WORKSPACE_ROOT/tsurilog-native}"
VARIANT="${QA_VARIANT:-development}"
PLATFORM="${FINGERPRINT_PLATFORM:-ios}"
CACHE_DIR="$WORKSPACE_ROOT/harness-engineering/assessment"
CACHE_FILE="$CACHE_DIR/.native-fingerprint-${VARIANT}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"

err() { printf '%s\n' "$*" >&2; }
emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source native-build-needed.sh --event "$1" --outcome "$2" --details "${3:-{\}}" || true
}

[[ -d "$NATIVE" ]] || { err "[build-needed] native ディレクトリなし: $NATIVE"; exit 1; }

# @expo/fingerprint の CLI を解決(ローカル bin 優先、無ければ npx --no-install)
fp_bin() {
    if [[ -x "$NATIVE/node_modules/.bin/fingerprint" ]]; then
        printf '%s' "$NATIVE/node_modules/.bin/fingerprint"
        return 0
    fi
    return 1
}

current_hash() {
    local bin
    if bin="$(fp_bin)"; then
        ( cd "$NATIVE" && "$bin" fingerprint:generate --platform "$PLATFORM" 2>/dev/null )
    elif command -v npx >/dev/null 2>&1; then
        ( cd "$NATIVE" && npx --no-install @expo/fingerprint fingerprint:generate --platform "$PLATFORM" 2>/dev/null )
    else
        return 1
    fi | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin)["hash"])
except Exception:
    sys.exit(1)' 2>/dev/null
}

cmd="${1:-check}"; shift || true

case "$cmd" in
    current)
        h="$(current_hash)" || { err "[build-needed] 指紋生成に失敗(@expo/fingerprint / node_modules を確認)"; exit 1; }
        printf '%s\n' "$h"
        ;;

    update)
        h="${1:-}"
        if [[ -z "$h" ]]; then
            h="$(current_hash)" || { err "[build-needed] 指紋生成に失敗"; exit 1; }
        fi
        mkdir -p "$CACHE_DIR" 2>/dev/null || true
        printf '%s\n' "$h" > "$CACHE_FILE"
        err "[build-needed] 指紋キャッシュを更新: $VARIANT → ${h:0:12}…"
        emit update ok "{\"variant\":\"$VARIANT\"}"
        ;;

    diff)
        bin="$(fp_bin)" || { err "[build-needed] fingerprint CLI なし"; exit 1; }
        if [[ ! -f "$CACHE_FILE" ]]; then
            err "[build-needed] キャッシュ未作成。先に build:run → update してください。"
            exit 1
        fi
        # @expo/fingerprint は diff 用に過去の fingerprint(JSON) が要るが、ここでは
        # hash しか保持しないため、人間向けには current を出して比較を促す。
        err "[build-needed] cached(${VARIANT}): $(cat "$CACHE_FILE")"
        err "[build-needed] current        : $(current_hash)"
        ;;

    check)
        cur="$(current_hash)" || { err "[build-needed] 指紋生成に失敗(@expo/fingerprint / node_modules を確認)"; exit 1; }
        if [[ ! -f "$CACHE_FILE" ]]; then
            err "[build-needed] 指紋キャッシュ無し(variant=$VARIANT)。dev-client の初回 build が必要。"
            echo "needed"
            emit check needed "{\"variant\":\"$VARIANT\",\"reason\":\"no_cache\"}"
            exit 10
        fi
        cached="$(cat "$CACHE_FILE")"
        if [[ "$cur" == "$cached" ]]; then
            err "[build-needed] 指紋一致 → build 不要(JS/TS のみの変更。Metro 配信で反映)"
            echo "skip"
            emit check skip "{\"variant\":\"$VARIANT\"}"
            exit 0
        else
            err "[build-needed] 指紋相違 → build 必要(ネイティブ依存が変わった)"
            err "                cached : ${cached:0:12}…"
            err "                current: ${cur:0:12}…"
            echo "needed"
            emit check needed "{\"variant\":\"$VARIANT\",\"reason\":\"hash_changed\"}"
            exit 10
        fi
        ;;

    -h|--help)
        sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
        ;;

    *)
        err "[build-needed] 不明なサブコマンド: $cmd (check|current|update|diff)"
        exit 1
        ;;
esac
