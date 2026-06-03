#!/usr/bin/env bash
#
# ai-strategy-eval.sh — AI戦略(事前戦略)の品質を釣法ごとに評価する軽量ハーネス
#
# 目的:
#   「釣法辞典(resources/ai/fishing-knowledge.md)」で grounding した戦略が、
#   各釣法の本質(狙うレンジ・メカニズム)に沿っているかを、シナリオ + キーワード判定で
#   自動チェックする。紀州釣り→中層、のような重大なズレを回帰として検知する。
#
# 注意:
#   - 実 Claude を叩く(課金・非決定的)。CI 常時ではなく、プロンプト/辞典の改修時に手動実行。
#   - キーワード判定は粗いヒューリスティック(重大な誤りの検知用)。最終判断は人間。
#
# 使い方:
#   TSURILOG_DEV_API_TOKEN=<token> ai-strategy-eval.sh
#
# 環境変数:
#   API_BASE  既定 http://localhost:8080
#   TSURILOG_DEV_API_TOKEN  ユーザーの api_token(必須)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_BASE="${API_BASE:-http://localhost:8080}"
TOKEN="${TSURILOG_DEV_API_TOKEN:-00000000-0000-4000-8000-000000000001}"
EFFECTIVENESS_LOG="$SCRIPT_DIR/effectiveness-log.sh"

err() { printf '%s\n' "$*" >&2; }

# シナリオ: name|fish_id|fishing_style|includes_any(複数は ,)|excludes(複数は ,)
# includes_any: いずれか1つ以上を含めば合格(本質レンジ/メカニズムの語彙)
# excludes: 1つでも「主軸として」含むと要確認(粗い検知)
read -r -d '' SCENARIOS <<'EOF'
紀州釣り(底+団子)|10|紀州釣り(ダンゴ釣り)|底,ボトム,着底,這わ,底取り|
エギング|9|エギング|エギ,シャク,フォール,着底,底|
サビキ|1|サビキ釣り|サビキ,コマセ,カゴ,表層,中層|
ジギング青物|5|ジギング(メタルジグ)|ジャーク,フォール,着底,ジグ|
投げ釣りキス|9|ちょい投げ(投げ釣り)|底,砂,天秤,さび|
EOF

PASS=0; FAIL=0
err "🎣 AI戦略 品質評価(釣法辞典 grounding) — API_BASE=$API_BASE"
err "============================================================"

while IFS='|' read -r name fish style includes excludes; do
    [[ -z "$name" ]] && continue
    body=$(python3 -c "
import json,sys
print(json.dumps({
  'fish_id': int('$fish'),
  'fishing_style': '''$style''',
  'lat': 34.30, 'lng': 135.18,
  'start_datetime': '2026-06-10T05:00:00+09:00',
  'end_datetime': '2026-06-10T10:00:00+09:00'
}, ensure_ascii=False))
")
    resp=$(curl -s -m 120 -X POST "$API_BASE/api/ai-strategy/pre-trip" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" \
        -d "$body")

    verdict=$(printf '%s' "$resp" | python3 -c "
import sys,json
inc='''$includes'''.split(',') if '''$includes''' else []
exc='''$excludes'''.split(',') if '''$excludes''' else []
try:
    d=json.load(sys.stdin); s=d.get('strategy') or {}
    if not d.get('is_success'):
        print('ERR '+str(d.get('error_message'))); sys.exit()
    full=' '.join([s.get('overall_judgement',''),s.get('best_time_window',''),s.get('recommended_spot',''),
      ' '.join(x.get('description','') for x in s.get('approach_steps',[])),s.get('recommended_tackle',''),s.get('cautions','')])
    inc_ok = (not inc) or any(k.strip() and k.strip() in full for k in inc)
    exc_bad = [k.strip() for k in exc if k.strip() and k.strip() in full]
    print(('PASS' if inc_ok and not exc_bad else 'FAIL')+' includes='+str(inc_ok)+' excludes_hit='+str(exc_bad))
except Exception as e:
    print('ERR parse '+str(e))
")
    if [[ "$verdict" == PASS* ]]; then PASS=$((PASS+1)); mark="✅"; else FAIL=$((FAIL+1)); mark="❌"; fi
    err "$mark $name [$style] → $verdict"
done <<< "$SCENARIOS"

err "============================================================"
err "結果: PASS=$PASS / FAIL=$FAIL"
[[ -x "$EFFECTIVENESS_LOG" ]] && "$EFFECTIVENESS_LOG" emit --source ai-strategy-eval.sh --event eval --outcome "$([[ $FAIL -eq 0 ]] && echo pass || echo fail)" --details "{\"pass\":$PASS,\"fail\":$FAIL}" || true
[[ $FAIL -eq 0 ]]
