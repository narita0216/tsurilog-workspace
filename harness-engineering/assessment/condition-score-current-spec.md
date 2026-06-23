# 釣れる度（Condition Score / Catch Rate）現行仕様 — 2026-06 時点

> **目的**: ピボット(ADR-0011)で「一般重み(config駆動)へ再設計」する前提として、**現行の釣れる度がどう計算・表示されているか**を実装ベースで正確に整理する。
> **対象コード**: `GetAnalysisRateController`(算法本体) / `GetEnvData`(環境データ) / `ConditionScoreService`(コンディション根拠) / native `app/analysis.tsx`・`HourlyCatchRateChart`・`utils/analysis-rate.ts`。
> ※ 本書は「現状」。再設計の方針は ADR-0011 / `initiatives/2026-06-pivot-condition-score-monetization.md`。

---

## 1. 全体像

「釣れる度」は **ある地点・ある日について、0〜23時の各時刻の“釣れやすさ”を 0〜100 のスコアで返す**機能。
- スコアは**偏差スコア**（50 = 全体平均と同じ。50超=平均より釣れやすい時間帯）。確率%ではない。
- 計算は**実データ(records/logs)由来**：「その時刻の環境9条件の値」が、過去の釣果ログでどれだけ“釣れている”条件かを集計して相対評価する。
- **データ較正型**のため、記録が少ないと各条件が baseline に寄り、スコアは 50 付近に潰れる（＝現状ほぼ機能していない＝ピボットの動機）。
- 別系統で `ConditionScoreService` が **AI非依存の「コンディションの良さ」根拠(◎○△＋マズメ)** を返す（こちらは一般ヒューリスティック。§6）。

---

## 2. API 契約

### `GET /api/analysis/rate`（偏差スコアの本体）
- 認証: 要(api_token)。コントローラ: `GetAnalysisRateController@index`。
- **Request**（`GetAnalysisRateRequest`）:
  | param | 必須 | 説明 |
  |---|---|---|
  | `lat` / `lng` | ○ | 対象地点（-90..90 / -180..180） |
  | `date` | ○ | 対象日 |
  | `fish_id` | 任意 | **未指定＝全魚種まとめて「何か釣れた率」**。初心者向けに魚種は実質廃止 |
  | `only_mesh_5km` | 任意 | `"true"` でその5kmメッシュ内の記録のみで算出。**廃止予定（常に全記録が既定）** |
- **Response**:
  ```json
  {
    "is_success": true,
    "error_message": "",
    "is_show": true,                 // false=釣行データ不足で非表示
    "rate_data": [
      { "hour": 0, "rates": { "all_rate": 52.3, "condition_rates": { "weather_id": 40.0, ... } } },
      ... 0〜23時
    ]
  }
  ```
- native は `is_show !== false` を `isShow`、`rate_data` を 0〜23時に整列(`normalizeRateData`)した `rows` に正規化（`use-analysis` / `RateQueryPayload`）。

### `GET /api/analysis/env_data`（環境データ＝条件の素）
- 9条件＋潮位(タイドグラフ用 `tide_height`)を時間別に返す。詳細は別資料、データ源は ADR-0007。

### `GET /api/analysis/condition_stats`（条件別の釣れ率テーブル・関連）
- 条件カテゴリ別の釣れ率集計（参考表示）。※本書では未詳細化（rate 本体と算法思想は共通）。

---

## 3. 9条件（スコアの軸）

`GetAnalysisRateController::getEnvData()` が env_cache を以下9キーに変換し、各キーで集計する。
`logs` テーブルは釣果時の同名カラムを保持しており、`where('logs.<condition>', <envValue>)` で突合する。

| # | キー | 元(env_cache) | 値の形 | データ源(ADR-0007) |
|---|---|---|---|---|
| 1 | `month` | date→month | 1–12 | 釣行日 |
| 2 | `hour` | hour | 0–23 | 対象時刻 |
| 3 | `tid_type_id` | tid_type | マスタID(中潮/大潮/小潮/長潮/若潮) | tide736 |
| 4 | `tid_action_id` | tid_action | マスタID(干潮/上げ3分/上げ7分/満潮/下げ3分/下げ7分) | WorldTides extremes |
| 5 | `weather_id` | weather | マスタID(晴/曇/雨/雪…) | Open-Meteo |
| 6 | `temperature` | temperature | ℃(整数) | Open-Meteo |
| 7 | `water_temperature` | water_temperature | ℃(整数) | Open-Meteo(marine) |
| 8 | `wind_speed_id` | wind_speed | マスタID(風速バケット) | Open-Meteo |
| 9 | `wave_height_id` | wave_height | マスタID(波高バケット) | Open-Meteo(marine) |

> コード上 5〜9 に「今後、有料化予定」コメントあり（＝ピボットの「種別/深掘りは有料」と整合する余地）。

---

## 4. アルゴリズム（偏差スコア方式）

時刻ごと(0〜23)に以下を計算する。

### 4.1 全体平均 baseline（基準）
```
baseline = 釣果ログ件数(is_caught=YES, fish_id指定時はその魚種) / 全ログ件数   (0〜1)
```
- 母数は `logs JOIN records`（`only_mesh_5km` 指定時はその5kmメッシュに限定）。
- 全ログ0件なら baseline = 0。

### 4.2 条件ごとの相対スコア（9条件それぞれ）
各条件 `cond` について、その時刻の env 値 `envValue` で絞った集計を取る:
```
totalCount  = logs[cond == envValue] の件数
caughtCount = そのうち is_caught=YES（fish_id 指定時はその魚種）

# 参考表示用の生の条件別釣れ率(%)
condition_rates[cond] = totalCount>0 ? caughtCount/totalCount*100 : 0

# ベイズ平滑化した条件別釣れ率(0〜1)。少サンプルは baseline へ寄る
smoothed = (caughtCount + K * baseline) / (totalCount + K)        # K = SMOOTHING_K = 8

# baseline との相対(偏差) 0〜100（baselineと同じ=50、低いほど0、高いほど100）
rel = 100 * smoothed^G / (smoothed^G + baseline^G)               # G = CONTRAST_G = 2.0
      (分母0なら rel = 50)
```

### 4.3 9条件を平均 → コントラスト拡大 → クランプ
```
avg      = (9条件の rel の合計) / 9
all_rate = clamp( 50 + (avg - 50) * FINAL_GAIN , 0, 100 )         # FINAL_GAIN = 1.4
```

### 4.4 チューニング定数（コントローラ定数・現行値）
| 定数 | 値 | 役割 |
|---|---|---|
| `SMOOTHING_K` | 8 | ベイズ平滑化の擬似件数。母数が小さい条件を baseline(中立50)へ寄せ極端な振れを抑える。小さいほど各条件が自分のデータを主張(差は出るがノイズ増) |
| `CONTRAST_G` | 2.0 | 偏差写像のべき勾配。>1 で平均から離れた条件を強く振る |
| `FINAL_GAIN` | 1.4 | 9条件平均で50に回帰した分を引き戻すコントラスト拡大率 |

---

## 5. is_show（表示可否）
- **そのスポットに「終了済み釣行(STATUS_FINISHED)」かつ「釣果ログ(is_caught=YES、fish_id指定時はその魚種)」が1件以上**あれば `true`。
- `only_mesh_5km` 指定時はその5kmメッシュに限定。
- `false` のとき native は「この付近にはまだ釣行データが十分にありません」を表示しスコアを出さない。

---

## 6. ConditionScoreService（コンディション根拠・別系統）
- **AI非依存・原価ゼロの決定論スコアラ**。釣果実データではなく「条件の良さ」を ◎○△ の要素で示す（誇大を避ける設計）。
- 返すのは `factors`(各要素 rating 0/1/2 + note) と `best_window`(マズメの重なり)。総合スコア/星は**廃止済み**。
- 評価要素と現行ヒューリスティック:
  | 要素 | rating=2(◎) | rating=1(○) | rating=0(△) |
  |---|---|---|---|
  | 時合(マズメ) | 朝/夕マズメ窓に重なる | マズメに近い(±2.5h) | 日中中心 |
  | 潮の動き | 「N分」(動く) | 満潮/干潮(潮止まり前後) | — |
  | 潮回り | 大潮/中潮 | 若潮/小潮 | 長潮 |
  | 水温 | 13〜26℃ | 8〜13 / 26〜29℃ | それ以外 |
  | 風 | <3 m/s | 3〜6 m/s | >6 m/s |
  | 波 | <0.5 m | 0.5〜1.0 m | >1.0 m |
- マズメは緯度経度＋日付から日の出/日の入りを概算(Sunrise/Sunset Algorithm)して判定。
- **この一般ヒューリスティックは、ピボットの「A2 一般重み」再設計の有力な出発点**（既に種別非依存・一般生物学ベース）。

---

## 7. フロント表示（native）
- 画面: `app/analysis.tsx`（ピンの「データ分析」）。釣れる度グラフ → タイドグラフ(2026-06追加) → 環境データ の順。
- **`HourlyCatchRateChart`**: 24時間の `all_rate` 折れ線（react-native-svg）。y軸 0/25/50/75/100(50=「平均」線)。横スライド/タップで時刻選択 → 環境カード・タイドグラフが追従。`peakHour` に🔥。
- **言語化(`rateVerdict`)**: スコア→ことば+絵文字+色。
  | スコア | ラベル |
  |---|---|
  | ≥68 | 🔥 好調 |
  | ≥56 | 🎣 良い |
  | ≥44 | 🙂 ふつう |
  | ≥32 | 😐 ひかえめ |
  | <32 | 😴 渋い |
- `normalizeRateData`: rate_data を 0〜23時に整列（欠損は0埋め、all_rate は0〜100クランプ）。`findPeakHourIndex`: all_rate 最大の時刻（同値は若い時刻）。
- 見せ方は**質的・方向性**（偏差スコア＋ことば）。精密な符号付き分解は出していない（ADR-0011 の鉄則と整合）。

---

## 8. 現行の特性・限界（再設計で効く論点）
- **データ較正型ゆえ記録依存**。記録者≒2人＝logs が薄く、baseline と条件別がほぼ同じ → `rel≒50` → 平均も50 → `FINAL_GAIN` で多少振れるが**実質ほぼ平坦**。これがピボットの直接の動機。
- **魚種は実質廃止**（`fish_id` 任意・既定は全魚種「何か釣れた率」）。種別は今後の有料軸。
- **`only_mesh_5km` は廃止予定**（常に全記録で算出）。
- 9条件は**マスタID/整数バケット**で突合（生値 raw_* は env_cache にあるが rate 算法では未使用。`ConditionScoreService` は raw を使用）。
- スコアは**確率ではなく偏差**。「robust(質的)に見せる」方針なので符号付き精密分解は出さない。

---

## 9. ピボット(ADR-0011)で触る所
- **A2 一般重み(無料スコア)**: 現行の「データ較正(偏差スコア)」を待たず、`ConditionScoreService` 的な**種別横断ヒューリスティックを config 駆動**で `all_rate` 相当に載せる。較正は後付け可能な構造に。
- **A3 種別スコア(有料¥150)**: 魚種テーブル(適水温/時期/潮選好…)で9条件の重みを切り替え、**選んだ瞬間に体感で変わる**こと。
- **見せ方**: robust(質的・方向性)を維持。`HourlyCatchRateChart` / `rateVerdict` はそのまま活かせる。
- 差し替えの中心は `GetAnalysisRateController::calculateRate`（または新スコアサービス）と config/魚種テーブル。`is_show`・フロント表示は再利用可能。
</content>
