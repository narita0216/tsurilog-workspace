#!/usr/bin/env bash
#
# contract-check.sh — API コントラクトの 3 点同期チェック
#
# 釣りログは「アプリ(tsurilog-native)」と「API(tsurilog-backend)」が
# REST API でのみ繋がる。両者の唯一の契約面は HTTP エンドポイントであり、
# その定義は 3 箇所に分散している:
#
#   1. tsurilog-backend/routes/api.php        … 実装の真実(Laravel のルート)
#   2. tsurilog-native/api/**/*.ts            … アプリが叩くクライアント
#   3. tsurilog-backend/openapi.yml           … 仕様書(ドキュメント)
#
# この 3 つはコードレビューだけでは静かにズレる(実際に openapi.yml の
# /analysis/* が routes と乖離している)。本スクリプトは 3 箇所を機械的に
# 突き合わせ、ドリフトを検出する。設計背景は ADR-0002。
#
# 使い方:
#   contract-check.sh              … 人間/AI 向けの全レポート(常に exit 0)
#   contract-check.sh --quiet      … SessionStart hook 用。ドリフトがあれば
#                                     1 行サマリのみ出力、無ければ無音
#   contract-check.sh --strict     … アプリが叩くのに backend に無いルート
#                                     (= 実害あるバグ)があれば exit 1
#
# 依存: python3(macOS 標準)。docker は不要(純粋なテキスト解析)。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"

BACKEND="${TSURILOG_BACKEND_DIR:-$WORKSPACE_ROOT/tsurilog-backend}"
NATIVE="${TSURILOG_NATIVE_DIR:-$WORKSPACE_ROOT/tsurilog-native}"

MODE="report"
case "${1:-}" in
    --quiet)  MODE="quiet" ;;
    --strict) MODE="strict" ;;
    -h|--help)
        sed -n '2,30p' "$0"; exit 0 ;;
esac

emit() {
    [[ -x "$EFFECTIVENESS_LOG" ]] || return 0
    "$EFFECTIVENESS_LOG" emit --source contract-check.sh --event check --outcome "$1" --details "${2:-{\}}" || true
}

ROUTES_FILE="$BACKEND/routes/api.php"
OPENAPI_FILE="$BACKEND/openapi.yml"

if [[ ! -f "$ROUTES_FILE" ]]; then
    [[ "$MODE" == "quiet" ]] || echo "[contract-check] routes/api.php が見つかりません: $ROUTES_FILE" >&2
    exit 0
fi

python3 - "$ROUTES_FILE" "$OPENAPI_FILE" "$NATIVE/api" "$MODE" <<'PY'
import os, re, sys

routes_file, openapi_file, native_api_dir, mode = sys.argv[1:5]

def norm(path):
    """エンドポイントパスを比較用に正規化する。
    - 先頭の /api を除去(native は /api 付き、Laravel routes は無し)
    - クエリ文字列を除去
    - パスパラメータ({id} / ${data.x} / :id)を :p に統一
    - 末尾スラッシュ除去
    underscore と hyphen は **保持** する(env_data vs env-data のドリフトを検出するため)
    """
    p = path.strip()
    p = p.split('?', 1)[0]
    if not p.startswith('/'):
        p = '/' + p
    if p.startswith('/api/'):
        p = p[4:]
    elif p == '/api':
        p = '/'
    segs = []
    for s in p.split('/'):
        if not s:
            continue
        if s.startswith('{') or s.startswith('$') or s.startswith(':') or '${' in s:
            segs.append(':p')
        else:
            segs.append(s)
    out = '/' + '/'.join(segs)
    if len(out) > 1 and out.endswith('/'):
        out = out[:-1]
    return out

# 1) Laravel routes
routes = set()  # (VERB, normpath)
route_re = re.compile(r"Route::(get|post|put|patch|delete)\(\s*['\"]([^'\"]+)['\"]")
with open(routes_file, encoding='utf-8') as f:
    for m in route_re.finditer(f.read()):
        routes.add((m.group(1).upper(), norm(m.group(2))))

# 2) native client calls
native = set()  # (VERB, normpath)
call_re = re.compile(r"apiClient\.(get|post|put|patch|delete)\(\s*[`'\"]([^`'\"]+)")
if os.path.isdir(native_api_dir):
    for root, _, files in os.walk(native_api_dir):
        for fn in files:
            if not fn.endswith('.ts'):
                continue
            with open(os.path.join(root, fn), encoding='utf-8') as f:
                for m in call_re.finditer(f.read()):
                    native.add((m.group(1).upper(), norm(m.group(2))))

# 3) openapi paths (verb 抜きの path 集合として扱う)
openapi = set()
if os.path.isfile(openapi_file):
    in_paths = False
    with open(openapi_file, encoding='utf-8') as f:
        for line in f:
            if re.match(r'^paths:\s*$', line):
                in_paths = True
                continue
            if in_paths:
                # 次のトップレベルキーで paths セクション終了
                if re.match(r'^\S', line) and not line.startswith(' '):
                    in_paths = False
                    continue
                m = re.match(r'^  (/\S+):\s*$', line)
                if m:
                    openapi.add(norm(m.group(1)))

route_paths = {p for _, p in routes}
native_paths = {p for _, p in native}

# 突き合わせ
app_missing_route = sorted(native - routes)          # アプリが叩くのに route が無い(実害)
route_unused_by_app = sorted(routes - native)        # route はあるがアプリ未使用(情報)
route_not_in_openapi = sorted(route_paths - openapi) # 仕様書に未記載のエンドポイント
openapi_not_in_route = sorted(openapi - route_paths) # 仕様書にあるが実在しない(stale)

def fmt_vp(pairs):
    return "\n".join(f"  - {v:6} {p}" for v, p in pairs) if pairs else "  (なし)"

def fmt_p(paths):
    return "\n".join(f"  - {p}" for p in paths) if paths else "  (なし)"

drift = len(app_missing_route) + len(route_not_in_openapi) + len(openapi_not_in_route)

if mode == "quiet":
    if drift:
        bits = []
        if app_missing_route:   bits.append(f"app→missing route {len(app_missing_route)}")
        if openapi_not_in_route:bits.append(f"openapi stale {len(openapi_not_in_route)}")
        if route_not_in_openapi:bits.append(f"undocumented {len(route_not_in_openapi)}")
        print(f"[contract-check] ⚠️ API コントラクトのドリフト: {', '.join(bits)}。`/contract-check` で詳細。")
    # quiet 時は終了コードで状態を返さない(SessionStart を止めない)
    sys.exit(0)

print("🎣 API コントラクト 3 点チェック (routes / native / openapi)")
print("=" * 60)
print(f"  Laravel routes  : {len(routes)} endpoints")
print(f"  native client   : {len(native)} calls")
print(f"  openapi paths   : {len(openapi)} paths")
print()

print(f"🔴 アプリが叩くのに backend に該当ルートが無い ({len(app_missing_route)}) — 実害(404)の可能性")
print(fmt_vp(app_missing_route))
print()

print(f"🟠 openapi に記載があるが実ルートに存在しない ({len(openapi_not_in_route)}) — stale な仕様書")
print(fmt_p(openapi_not_in_route))
print()

print(f"🟡 実ルートだが openapi 未記載 ({len(route_not_in_openapi)}) — ドキュメント不足")
print(fmt_p(route_not_in_openapi))
print()

print(f"⚪ backend にあるがアプリ未使用 ({len(route_unused_by_app)}) — 参考情報(問題とは限らない)")
print(fmt_vp(route_unused_by_app))
print()

if drift == 0:
    print("✅ ドリフトなし。3 点は整合しています。")
else:
    print(f"⚠️ 合計 {drift} 件のドリフトを検出。詳細は ADR-0002 / findings を参照。")

# strict: 実害ある app→missing のみで非ゼロ
if mode == "strict" and app_missing_route:
    sys.exit(1)
sys.exit(0)
PY
rc=$?

if [[ "$MODE" != "quiet" ]]; then
    if [[ $rc -eq 0 ]]; then emit ok; else emit drift '{"strict_fail":true}'; fi
fi
exit $rc
