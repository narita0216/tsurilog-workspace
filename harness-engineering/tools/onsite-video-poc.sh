#!/usr/bin/env bash
#
# onsite-video-poc.sh — 現地戦略(on-site)の動画解析を実 API で検証する PoC
#
# 目的:
#   テスト動画を on-site エンドポイントに multipart 送信し、
#     1) Gemini File API / inline の挙動(大容量は File API 経路を通るか)
#     2) 動画から波/海面/地形を把握する解析品質(ai_strategies.video_summary)
#     3) それを踏まえた Claude の現地戦略
#   をローカル backend(feature/ai-strategy)で確認する。native(実機カメラ)を介さずに
#   backend 側の動画パイプライン品質を検証できる(iOS Simulator にカメラが無いため)。
#
# 前提: ローカル backend 稼働(docker-compose-local, :8080)、ANTHROPIC/GEMINI キー設定済み、
#       テストユーザー(既定 token=qa_tester の api_token)が存在。
#
# 使い方:
#   onsite-video-poc.sh <video-path> [lat] [lng] [fish_id] [fishing_style_id]
#
# 環境変数:
#   API_BASE   既定 http://localhost:8080
#   TOKEN      既定 00000000-0000-4000-8000-000000000001 (qa_tester)
#   FORCE_FILE_API=1  backend の GEMINI_INLINE_MAX_BYTES を 1 にして File API を強制
#                     (小さいテスト動画でも File API 経路を確認したいとき)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BACKEND="${TSURILOG_BACKEND_DIR:-$WORKSPACE_ROOT/tsurilog-backend}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"
API_BASE="${API_BASE:-http://localhost:8080}"
TOKEN="${TOKEN:-00000000-0000-4000-8000-000000000001}"
COMPOSE="docker compose -f docker-compose-local.yml"

err() { printf '%s\n' "$*" >&2; }
emit() { [[ -x "$EFFECTIVENESS_LOG" ]] && "$EFFECTIVENESS_LOG" emit --source onsite-video-poc.sh --event "$1" --outcome "$2" || true; }

VIDEO="${1:-}"
LAT="${2:-35.16}"
LNG="${3:-139.61}"
FISH="${4:-1}"
STYLE="${5:-1}"

[[ -n "$VIDEO" && -f "$VIDEO" ]] || { err "使い方: onsite-video-poc.sh <video-path> [lat] [lng] [fish_id] [fishing_style_id]"; err "  テスト動画が見つかりません: $VIDEO"; exit 1; }

size=$(wc -c < "$VIDEO" | tr -d ' ')
err "[onsite-poc] video=$VIDEO size=$((size/1024))KB  → $([[ $size -gt $((7*1024*1024)) ]] && echo 'File API 経路(>7MB)' || echo 'inline 経路(<=7MB)')"

if [[ "${FORCE_FILE_API:-0}" == "1" ]]; then
    err "[onsite-poc] FORCE_FILE_API=1 → GEMINI_INLINE_MAX_BYTES=1 を一時設定(File API 強制)"
    ( cd "$BACKEND" && $COMPOSE exec -T api bash -lc 'grep -q "^GEMINI_INLINE_MAX_BYTES=" .env && sed -i "s/^GEMINI_INLINE_MAX_BYTES=.*/GEMINI_INLINE_MAX_BYTES=1/" .env || echo "GEMINI_INLINE_MAX_BYTES=1" >> .env; php artisan config:clear >/dev/null 2>&1' ) || true
fi

err "[onsite-poc] POST $API_BASE/api/ai-strategy/on-site (実 Gemini + Claude。30-90s)…"
resp=$(curl -s -m 180 -X POST "$API_BASE/api/ai-strategy/on-site" \
    -H "Authorization: Bearer $TOKEN" \
    -F "fish_id=$FISH" -F "fishing_style_id=$STYLE" \
    -F "lat=$LAT" -F "lng=$LNG" \
    -F "free_text=PoC: テスト動画での現地戦略" \
    -F "video=@$VIDEO;type=video/mp4")

echo "$resp" | python3 -m json.tool 2>/dev/null || echo "$resp"

err ""
err "=== Gemini の動画解析サマリ(品質確認: 波/海面/地形を捉えているか) ==="
( cd "$BACKEND" && $COMPOSE exec -T db psql -U tsurilog_user -d tsurilog -t -c \
    "select id, model, coalesce(video_summary,'(なし)') from ai_strategies where kind='on_site' order by id desc limit 1;" 2>/dev/null ) || err "(DB 取得失敗)"

echo "$resp" | grep -q '"is_success":true\|"is_success": true' && emit poc ok || emit poc fail
