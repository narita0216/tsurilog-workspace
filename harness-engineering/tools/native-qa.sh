#!/usr/bin/env bash
#
# native-qa.sh — 釣りログ native の dev-client 自動QA(シミュレータ起動 + スクショ撮影)
#
# AI が「実装に関わる画面」を iOS シミュレータで通り、スクショを撮る。スクショは
# 実質 E2E の証跡として PR に添付され、人間レビューのコストを下げる(ADR-0008)。
#
# ★ 無料枠の鉄則(重要):
#   - **シミュレータ QA のビルドは `npx expo run:ios`(ローカル / Xcode)= EAS の無料枠を
#     一切消費しない。** これを既定の build 経路にする。`build` サブコマンドで実行。
#   - `eas build`(=ビルド枠を消費)は **この script からは実行しない**。実機配布が要る
#     ときだけ人間が明示実行する。`eas build:run`(枠を消費しない DL+install)は `install`
#     サブコマンドで対応(EAS で作った成果物を使う場合)。
#   - JS/TS だけの変更は build 不要 → Metro 配信で反映(native-build-needed.sh が指紋判定)。
#
# 使い方:
#   native-qa.sh build [opts]    # ★ローカルビルド(expo run:ios)で dev-client を simulator に
#                                #   install + 指紋更新。無料。ネイティブ変更時/初回に使う。
#   native-qa.sh run [opts]      # 既定。指紋判定 → (skip なら) Metro + Maestro + スクショ
#                                #   needed なら build を促す(自走で長時間ビルドはしない)
#   native-qa.sh install [opts]  # eas build:run -p ios --latest(EAS 成果物を DL+install。枠消費なし)
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

# expo run:ios の pod install は system Ruby の ffi gem がアーキ不整合だと失敗する
# (Apple Silicon + Intel Homebrew 混在環境の典型)。brew 版 cocoapods を PATH 前置で
# 優先させて回避する。詳細 → findings/2026-06-02-native-devclient-qa-maestro.md
ensure_cocoapods() {
    if command -v brew >/dev/null 2>&1; then
        local pbin; pbin="$(brew --prefix cocoapods 2>/dev/null)/bin"
        if [[ -x "$pbin/pod" ]]; then
            export PATH="$pbin:$PATH"
            note "brew 版 CocoaPods を PATH 前置: $pbin ($("$pbin/pod" --version 2>/dev/null))"
        fi
    fi
}

# maestro は JDK を要求する。JAVA_HOME 未設定でも brew の openjdk を自動で拾う。
ensure_java() {
    if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then return 0; fi
    command -v java >/dev/null 2>&1 && /usr/libexec/java_home >/dev/null 2>&1 && return 0
    if command -v brew >/dev/null 2>&1; then
        local jdk; jdk="$(brew --prefix openjdk 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
        if [[ -x "$jdk/bin/java" ]]; then
            export JAVA_HOME="$jdk"; export PATH="$jdk/bin:$PATH"
            note "JAVA_HOME を brew openjdk に設定: $jdk"
            return 0
        fi
    fi
    return 1
}

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
# ★ スクショ成果物はアプリリポではなく workspace(ハーネス)に保存する(チーム方針)。
[[ -n "$SHOTS_DIR" ]] || SHOTS_DIR="$WORKSPACE_ROOT/harness-engineering/qa-artifacts/$ts"

# =============================================================================
# build: ★ローカルビルド(expo run:ios)で dev-client を simulator に install。無料。
#   EAS の枠を消費しない。ネイティブ依存変更時・初回に使う。
# =============================================================================
do_build() {
    have npx || { err "[native-qa] npx(Node.js)が必要です"; exit 1; }
    have xcrun || { err "[native-qa] Xcode CLT が必要です"; exit 1; }
    note "ローカルビルド(expo run:ios)で dev-client を simulator に install します(EAS 枠消費なし)"
    note "初回は prebuild + pod install + xcodebuild で時間がかかります(~10-25分)"
    ensure_cocoapods   # system Ruby の ffi アーキ不整合を回避(brew cocoapods 優先)
    # dev variant の bundle id / GoogleService を使うため variant を明示
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '\033[90m  $ (cd %s && EXPO_PUBLIC_APP_VARIANT=development npx expo run:ios --device %s)\033[0m\n' "$NATIVE" "$DEVICE" >&2
    else
        ( cd "$NATIVE" && EXPO_PUBLIC_APP_VARIANT=development npx expo run:ios --device "$DEVICE" ) || {
            err "[native-qa] expo run:ios に失敗。pod install / xcodebuild ログを確認。"
            emit build fail; exit 1
        }
    fi
    run "$BUILD_NEEDED" update
    note "ローカルビルド完了 + 指紋キャッシュ更新。以降この指紋なら build 不要(Metro 配信)。"
    emit build ok
}

# =============================================================================
# install: EAS で作った既存成果物をシミュレータに入れる(枠を消費しない build:run)。
#   通常は do_build(ローカル)で十分。EAS 成果物を使いたいときだけ。
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

    # ここに来た = build needed。ローカルビルドは無料だが長時間(~10-25分)なので、
    # run の中で自走せず、明示的な build サブコマンドに誘導する。
    warn "ネイティブ依存が変わった or 初回のため dev-client のビルドが必要です。"
    err  ""
    err  "  ★ ローカルビルド(無料・EAS 枠を消費しない):"
    err  "       $0 build --device $DEVICE"
    err  "     → 完了後にもう一度: $0 run"
    err  ""
    err  "  (EAS 成果物を使う場合のみ: eas build -p ios --profile $SIM_PROFILE → $0 install)"
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
    have maestro || precond "maestro が必要です(brew install mobile-dev-inc/tap/maestro)"
    have maestro && { ensure_java || precond "maestro 実行に JDK が必要です(brew install openjdk)"; }
    have xcrun   || precond "xcrun(Xcode CLT)が必要です"
    [[ -f "$FLOW" ]] || precond "Maestro フローがありません: $FLOW(flow-template.yaml を .maestro/ に置く)"
    [[ -n "${TSURILOG_DEV_API_TOKEN:-}" ]] || precond "TSURILOG_DEV_API_TOKEN 未設定(検証先 backend で有効な api_token。既定=ローカル Docker で発行したトークン)"

    # ★ 検証先 API は既定でローカル Docker(§8.0: AI はローカルで検証)。未指定なら localhost:8080。
    #   dev/staging を検証したい時だけ呼び出し元で EXPO_PUBLIC_API_DOMAIN を明示上書きする。
    export EXPO_PUBLIC_API_DOMAIN="${EXPO_PUBLIC_API_DOMAIN:-http://localhost:8080}"
    note "検証先 API: $EXPO_PUBLIC_API_DOMAIN"

    # ★ dev-auth はトークンを注入しても REDIRECT が無いと画面遷移せずログイン画面に留まる。
    #   既定でホーム(/(tabs))へ着地させる。別画面を撮りたいフローは呼び出し元で上書きする
    #   (例: EXPO_PUBLIC_DEV_AUTH_REDIRECT=/analysis)。
    export EXPO_PUBLIC_DEV_AUTH_REDIRECT="${EXPO_PUBLIC_DEV_AUTH_REDIRECT:-/(tabs)}"
    note "dev-auth 着地: $EXPO_PUBLIC_DEV_AUTH_REDIRECT"

    note "スクショ出力先: $SHOTS_DIR"
    run mkdir -p "$SHOTS_DIR"

    # Metro をバックグラウンド起動(JS/TS 変更を配信)
    # ★ EXPO_PUBLIC_APP_VARIANT=development を必ず設定する。dev-auth ルートは
    #   __DEV__ かつ EXPO_PUBLIC_APP_VARIANT==="development" でのみ有効化されるため、
    #   .env に無いローカルビルドでも QA で確実に認証注入できるようにする。2026-06-02 検証。
    note "Metro を起動します(expo start --dev-client, port=$METRO_PORT, variant=development)"
    local metro_pid=""
    # ★ EXPO_PUBLIC_DEV_AUTH_TOKEN に dev トークンを渡し、deep-link/ダイアログに頼らず
    #   起動時に自動ログインさせる(use-dev-auth のフォールバック)。headless で確実。
    # ★ --clear で Metro の transform キャッシュを破棄。EXPO_PUBLIC_* はバンドル時に inline
    #   されるため、API 向き先(ローカル)やトークンを変えたのにキャッシュで反映されず
    #   ログイン画面のまま、という事故を防ぐ(2026-06-25 ローカル QA で踏んだ)。
    # ★ EXPO_PUBLIC_API_DOMAIN / EXPO_PUBLIC_DEV_AUTH_REDIRECT は呼び出し元の環境から継承
    #   (ローカル backend を指す: EXPO_PUBLIC_API_DOMAIN=http://localhost:8080 等)。
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '\033[90m  $ (cd %s && EXPO_PUBLIC_APP_VARIANT=development EXPO_PUBLIC_DEV_AUTH_TOKEN=*** npx expo start --dev-client --clear --port %s) &\033[0m\n' "$NATIVE" "$METRO_PORT" >&2
    else
        ( cd "$NATIVE" && EXPO_PUBLIC_APP_VARIANT=development EXPO_PUBLIC_DEV_AUTH_TOKEN="${TSURILOG_DEV_API_TOKEN:-}" npx expo start --dev-client --clear --port "$METRO_PORT" >/tmp/tsurilog-metro.log 2>&1 ) &
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

    # dev-client を Metro に接続(dev-client の deep link)。
    # ★ スキームは `exp+turilog://`(app scheme の `turilog://` ではない)。2026-06-02 実機確認。
    # ★ simctl openurl は「"釣りログ" で開きますか?」確認ダイアログを出す → Maestro 側で「開く」をタップ。
    local metro_url="http://localhost:$METRO_PORT"
    note "dev-client を Metro に接続: $metro_url(確認ダイアログは Maestro が「開く」で通過)"
    run xcrun simctl openurl "$DEVICE" "exp+turilog://expo-development-client/?url=$metro_url"
    [[ "$DRY_RUN" == "1" ]] || sleep 5

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
    build)   do_build ;;
    run)     do_run ;;
    install) do_install ;;
    check)   exec "$BUILD_NEEDED" check ;;
    -h|--help) usage ;;
    *) err "[native-qa] 不明なサブコマンド: $SUB (build|run|install|check)"; exit 1 ;;
esac
