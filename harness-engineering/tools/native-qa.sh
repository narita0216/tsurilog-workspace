#!/usr/bin/env bash
#
# native-qa.sh — 釣りログ native の dev-client 自動QA(シミュレータ起動 + スクショ撮影)
#
# AI が「実装に関わる画面」を iOS シミュレータで通り、スクショを撮る。スクショは
# 実質 E2E の証跡として PR に添付され、人間レビューのコストを下げる(ADR-0008)。
#
# ★ 無料枠の鉄則:
#   - `eas build`(=ビルド枠を消費)は **この script からは絶対に実行しない**。
#     build が必要と判定したら案内して停止し、ユーザーの明示実行に委ねる。
#   - `eas build:run`(=既にある成果物を DL して install。枠を消費しない)は実行する。
#   - JS/TS だけの変更は build 不要 → Metro 配信で反映(native-build-needed.sh が判定)。
#
# 使い方:
#   native-qa.sh run [opts]      # 既定。指紋判定 → (skip なら) Metro + Maestro + スクショ
#   native-qa.sh install [opts]  # eas build:run -p ios --latest で最新ビルドを install
#                                #   + 指紋キャッシュ更新(自分で eas build した直後に使う)
#   native-qa.sh check           # build 要否だけ表示(native-build-needed.sh check)
#
# opts:
#   --flow <path>        Maestro フロー(既定: tsurilog-native/.maestro/qa.yaml)
#   --shots-dir <path>   スクショ出力先(既定: tsurilog-native/qa-artifacts/<ts>)
#   --device <udid>      シミュレータ UDID(既定: booted)
#   --variant <name>     dev-client variant(既定: development)
#   --no-build           指紋判定を省略し、install 済み前提で QA に進む
#   --dry-run            実コマンドを実行せず、何をするかだけ表示(ロジック検証用)
#
# 環境変数:
#   TSURILOG_NATIVE_DIR     native リポのパス
#   TSURILOG_DEV_API_TOKEN  dev API で発行済みのテスト用 api_token(認証回避に必須)
#   QA_TIMESTAMP            スクショディレクトリ名に使うタイムスタンプ(未指定時は date)
#   METRO_PORT              Metro ポート(既定: 8081)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
NATIVE="${TSURILOG_NATIVE_DIR:-$WORKSPACE_ROOT/tsurilog-native}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"
BUILD_NEEDED="$SCRIPT_DIR/native-build-needed.sh"

VARIANT="development"                              # 指紋キャッシュの variant
SIM_PROFILE="${EAS_SIM_PROFILE:-development-simulator}"  # シミュレータ用 EAS build profile
FLOW=""
SHOTS_DIR=""
DEVICE="booted"
NO_BUILD=0
DRY_RUN=0
METRO_PORT="${METRO_PORT:-8081}"
APP_ID="com.narikei74.turilog.dev"   # dev variant の bundle id(app.config.ts)

err()  { printf '%s\n' "$*" >&2; }
note() { printf '\033[36m[native-qa]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33m[native-qa]\033[0m %s\n' "$*" >&2; }
emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source native-qa.sh --event "$1" --outcome "$2" --details "${3:-{\}}" || true
}
# 実行ラッパ。--dry-run のときは表示だけ。
run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '\033[90m  $ %s\033[0m\n' "$*" >&2
        return 0
    fi
    "$@"
}

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

# --- 引数パース --------------------------------------------------------------
SUB="${1:-run}"; shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --flow)       FLOW="$2"; shift 2 ;;
        --shots-dir)  SHOTS_DIR="$2"; shift 2 ;;
        --device)     DEVICE="$2"; shift 2 ;;
        --variant)    VARIANT="$2"; shift 2 ;;
        --no-build)   NO_BUILD=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) err "[native-qa] 不明な引数: $1"; exit 1 ;;
    esac
done

export QA_VARIANT="$VARIANT"

# --- 前提チェック ------------------------------------------------------------
[[ -d "$NATIVE" ]] || { err "[native-qa] native ディレクトリなし: $NATIVE"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ts="${QA_TIMESTAMP:-$(date -u +%Y%m%d-%H%M%S)}"
[[ -n "$FLOW" ]]      || FLOW="$NATIVE/.maestro/qa.yaml"
[[ -n "$SHOTS_DIR" ]] || SHOTS_DIR="$NATIVE/qa-artifacts/$ts"

# =============================================================================
# install: 既存の最新ビルドをシミュレータに入れる(枠を消費しない build:run)
# =============================================================================
do_install() {
    have eas || { err "[native-qa] eas CLI が必要です(npm i -g eas-cli → eas login)"; exit 1; }
    note "最新の simulator ビルドをシミュレータに install します(build:run = 枠消費なし, profile=$SIM_PROFILE)"
    if ! run eas build:run -p ios --latest --profile "$SIM_PROFILE"; then
        err "[native-qa] build:run に失敗。simulator 向けビルド(eas.json の ios.simulator:true)が"
        err "            存在するか、eas login 済みか確認してください。"
        emit install fail; exit 1
    fi
    # install できた = この指紋の dev-client がシミュレータに入った。キャッシュ更新。
    run "$BUILD_NEEDED" update
    note "install 完了 + 指紋キャッシュ更新。以降この指紋なら build 不要。"
    emit install ok
}

# =============================================================================
# build 要否ゲート
# =============================================================================
gate_build() {
    [[ "$NO_BUILD" == "1" ]] && { note "--no-build: 指紋判定をスキップ(install 済み前提)"; return 0; }
    [[ -x "$BUILD_NEEDED" ]] || { err "[native-qa] native-build-needed.sh がありません"; exit 1; }

    local decision
    decision="$("$BUILD_NEEDED" check 2>/dev/null)"; local code=$?
    if [[ "$decision" == "skip" && $code -eq 0 ]]; then
        note "build 不要(指紋一致)。Metro 配信で QA します。"
        return 0
    fi

    # ここに来た = build needed。★ eas build は自走しない。案内して停止。
    warn "ネイティブ依存が変わった or 初回のため dev-client の再ビルドが必要です。"
    warn "EAS の無料ビルド枠を消費するため、ビルドは手動で承認・実行してください:"
    err  ""
    err  "  1) ビルド(枠を消費):"
    err  "       (cd $NATIVE && eas build -p ios --profile $SIM_PROFILE)"
    err  "     ※ eas.json の $SIM_PROFILE は development を継承した simulator 用プロファイル"
    err  "  2) install + 指紋更新(枠は消費しない):"
    err  "       $0 install --variant $VARIANT"
    err  "  3) 再度 QA:"
    err  "       $0 run"
    err  ""
    emit gate needed "{\"variant\":\"$VARIANT\"}"
    exit 20
}

# =============================================================================
# QA 本体: Metro 起動 → dev-client を Metro に接続 → 認証注入 → Maestro → スクショ
# =============================================================================
do_run() {
    gate_build

    # 前提チェック(--dry-run のときは止めずに警告にとどめ、全経路を見せる)
    precond() {
        local msg="$1"
        if [[ "$DRY_RUN" == "1" ]]; then warn "(dry-run)前提未充足: $msg"; else err "[native-qa] $msg"; exit 1; fi
    }
    have maestro || precond "maestro が必要です(curl -fsSL https://get.maestro.mobile.dev | bash)"
    have xcrun   || precond "xcrun(Xcode CLT)が必要です"
    [[ -f "$FLOW" ]] || precond "Maestro フローがありません: $FLOW(flow-template.yaml を .maestro/ に置く)"
    [[ -n "${TSURILOG_DEV_API_TOKEN:-}" ]] || precond "TSURILOG_DEV_API_TOKEN 未設定(dev API 発行のテスト用 api_token を渡す)"

    note "スクショ出力先: $SHOTS_DIR"
    run mkdir -p "$SHOTS_DIR"

    # Metro をバックグラウンド起動(JS/TS 変更を配信)
    note "Metro を起動します(expo start --dev-client, port=$METRO_PORT)"
    local metro_pid=""
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '\033[90m  $ (cd %s && npx expo start --dev-client --port %s) &\033[0m\n' "$NATIVE" "$METRO_PORT" >&2
    else
        ( cd "$NATIVE" && npx expo start --dev-client --port "$METRO_PORT" >/tmp/tsurilog-metro.log 2>&1 ) &
        metro_pid=$!
        # Metro が立ち上がるのを待つ
        local i
        for i in $(seq 1 30); do
            curl -sf "http://localhost:$METRO_PORT/status" >/dev/null 2>&1 && break
            sleep 1
        done
    fi
    # 後始末: 終了時に Metro を止める(trap は do_run 終了後に発火するため global で保持)
    METRO_PID="$metro_pid"
    trap 'P="${METRO_PID:-}"; [[ -n "$P" ]] && kill "$P" 2>/dev/null || true' EXIT

    # dev-client を Metro に接続(dev-client の deep link)
    local metro_url="http://localhost:$METRO_PORT"
    note "dev-client を Metro に接続: $metro_url"
    run xcrun simctl openurl "$DEVICE" "turilog://expo-development-client/?url=$metro_url"
    [[ "$DRY_RUN" == "1" ]] || sleep 8   # JS バンドルのロード待ち

    # Maestro 実行(フロー内で dev-auth 注入 + takeScreenshot)
    note "Maestro フローを実行: $FLOW"
    local maestro_args=( test -e "DEV_API_TOKEN=${TSURILOG_DEV_API_TOKEN:-}" -e "SHOTS_DIR=$SHOTS_DIR" "$FLOW" )
    [[ "$DEVICE" != "booted" ]] && maestro_args=( --device "$DEVICE" "${maestro_args[@]}" )
    if run maestro "${maestro_args[@]}"; then
        note "QA 成功。スクショ: $SHOTS_DIR"
        if [[ "$DRY_RUN" != "1" ]]; then
            local n; n=$(find "$SHOTS_DIR" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
            note "撮影枚数: $n"
            emit run ok "{\"shots\":$n}"
        else
            emit run ok
        fi
    else
        err "[native-qa] Maestro フロー失敗。/tmp/tsurilog-metro.log と Maestro 出力を確認。"
        emit run fail
        exit 1
    fi
}

case "$SUB" in
    run)     do_run ;;
    install) do_install ;;
    check)   exec "$BUILD_NEEDED" check ;;
    -h|--help) usage ;;
    *) err "[native-qa] 不明なサブコマンド: $SUB (run|install|check)"; exit 1 ;;
esac
