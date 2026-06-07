# 初心者向けターゲット変更(分析簡素化 / ピンラベル / 最近の釣果ページング)

- 日付: 2026-06-07
- ブランチ: develop 起点の新ブランチ
  - backend: `feature/admin-analytics` … ではなく **`feature/beginner-focus`**(ローカルコミット `6280d5d`、push は owner reomin)
  - native: `feature/beginner-focus`(**push 済み** `f2724b8`)
- 背景: ターゲット/コンセプトを「初心者向け」に変更。魚種別・地点限定など複雑さを削ぎ、シンプルに。

## 実装サマリ
1. **釣果率を魚種非依存に**: `/analysis/rate` の `fish_id` を任意化。未指定で「何か釣れた率」を集計(`GetAnalysisRateController` / `calculateRate` を nullable 対応)。native は `get-rate` から fish_id を外した。
2. **分析画面を1画面に**: 環境/分析タブ・`only_mesh_5km` トグル・「効いている条件 TOP3」を廃止。釣果率グラフ(`HourlyCatchRateChart`)の下に環境カード(`EnvironmentTable`)を配置し、**グラフの横スクラブと環境カルーセルを双方向同期**(EnvironmentTable を `selectedHour`/`onSelectHour` で制御可能化)。**デフォルト選択は現在時刻**。
3. **ダッシュボード再構成**: 魚種選択と「今月の釣行」を廃止。**「お気に入りの釣り場」=保存ピン**(`FavoritePinCard`、タップで分析・鉛筆でラベル編集)。「最近の釣果」は**魚種無関係・最新順・5件+「さらに表示」**(新 `GET /recent_catches` + `useInfiniteQuery`)。「近場の釣り場」は残しつつ魚種非依存に。
4. **ピンのラベル**: `pins.label`(nullable)追加。保存時にクライアントで**最寄り釣り場を自動ラベル**(`nearestFishingPointLabel` ← 既存 `constants/fishing_points.ts` の503件・田ノ浦漁港等)。手動編集は `PUT /pins/{id}/label`(自分のピンのみ)。

## 設計判断
- **釣り場マスタは新設せず**、native に既にある `FISHING_POINTS`(503件, tide_points_500.csv 由来)＋`utils/geo-distance` の最寄り検索を活用してクライアント側で自動ラベル。DB 重複ゼロ・最短。ラベル文字列だけ `pins.label` に保存。
- /dashboard エンドポイントは温存(今は native 未使用)。recent は専用エンドポイントに分離。
- condition_stats / get-dashboard / use-dashboard は dead code として残置(削除はしていない)。

## 確認
- backend: 全201 green。contract-check **404リスク0**(新規 `/recent_catches`・`/pins/{id}/label` は openapi 記載済み。残ドリフトは既存分)。dev pg は `migrate`(pins.label)済み。
- native: `tsc --noEmit` / `expo lint` クリーン(0 error/0 warning)。
- **未実施: `/native-qa`(dev-client 実機/シミュレータでの目視確認)**。UI 変更が大きいため、ビルドして動線確認推奨(特に: 分析のグラフ↔環境カード同期、お気に入りピンのラベル編集、最近の釣果の「さらに表示」)。

## /native-qa 実施結果(2026-06-07・ローカルDB)
- 「再ビルド要否」: 私の差分は **JS/TS のみ**(api/app/components/hooks/types/utils)→ **再ビルド不要**。指紋が `needed` を返すのは、シミュレータの dev-client が develop の以前のネイティブ依存追加(expo-haptics 等)より古いため。私の変更が原因ではない。
- **ADR-0008 の native 側 QA 基盤が未実装だったことが判明** → 今回実装した:
  - `hooks/use-dev-auth.ts`(`turilog://dev-auth?token=` 注入、`__DEV__` 限定)。
  - ただし dev-client + 独自スキームの `simctl openurl` は iOS の「開きますか？」確認が出てヘッドレスで詰む → **`EXPO_PUBLIC_DEV_AUTH_TOKEN` での起動時自動ログイン fallback** を追加(これで確認ダイアログ不要)。
  - `.maestro/qa.yaml` フロー雛形を追加。
- 実行: ローカル Docker backend にQAユーザー/ピン2件/公開釣果8件を seed → `.env` を `http://localhost:8080` + dev トークンにして **`npx expo run:ios`(ローカルビルド・EAS無料枠不使用)** → シミュレータ起動 → 自動ログイン。
- **このQAで実バグを検出&修正**: backend は `pins.lat/lng` を decimal=**文字列**で返すため、`FavoritePinCard` の `pin.lat.toFixed()` が `is not a function` でクラッシュ。`Number()` で修正済み。
- 確認できた画面: ダッシュボード「お気に入りの釣り場」(ラベル付き/未設定ピンの表示、編集鉛筆)= 正常描画。証跡 `tsurilog-native/qa-artifacts/beginner-focus/dashboard-favorites.png`。
- **未確認(ツール制約)**: 「近場の釣り場」「最近の釣果(さらに表示)」「分析画面」は、シミュレータのシステムダイアログ(通知許可・dev-client オンボーディング)が被さり、タップ手段(**Maestro=Java 未導入 / cliclick 無し**)が無いため自動スクショ未取得。Java(JDK)導入 or 実機/手動で要確認。
- 環境メモ: Metro は CI モードだと redbox/Fast Refresh が効かず混乱したため、通常モードで起動推奨。`.env` は QA 後に dev ドメインへ復元済み。ローカル Docker DB にQA seed データが残存(ローカルのみ)。

## 追加対応(2026-06-07 第2ラウンド)
- **ピン自動ラベルが効かない根本原因**: 主経路のマップ保存モーダル `selected-pin-modal.tsx` が `label` を渡していなかった(分析画面のみ対応済みだった)。マップ/records も自動ラベルを付与。しきい値 2km→**8km**(ポイント間隔の中央値≈5.8km に合わせ実用化。p75=11.4km)。
- **分析画面のカクつき**: 環境カルーセル+時間ページネーションの FlatList スクロールとグラフの reanimated pan が双方向同期で競合 → **カルーセル/チップを廃止し「グラフのスライドだけ」で時間選択**、環境は選択時刻に追従する**単一 HourCard** に。日付選択を最上部(日付ピル)へ。釣果率は魚アイコン+大きな % でリッチ表示。
- ダッシュボードもセクション見出しにアイコン+アクセントでリッチ化。
- `use-dev-auth` に `EXPO_PUBLIC_DEV_AUTH_REDIRECT`(認証後の遷移先)を追加=ヘッドレスで特定画面に直行できる QA 補助(dev限定)。

### ヘッドレス UI QA の壁(重要・未解決)
- iOS Simulator の**システムダイアログ(位置情報許可・通知許可・dev-client オンボーディング)**が画面を覆い、これを閉じる**タップ自動化が本環境では全滅**:
  - Maestro = **JDK 未導入**で起動不可。
  - AppleScript/System Events = **アクセシビリティ権限なし**(-1719)。
  - `cliclick` = 導入したが、ウィンドウ座標取得が AX 依存で詰む。
  - `simctl privacy grant location-always` でも react-native-maps の許可ダイアログは抑止されなかった。
- 結果、ダッシュボード(お気に入り)は描画確認できたが、**分析画面のクリーンなスクショは未取得**。アプリ自体はシミュレータで稼働(QAユーザー自動ログイン→/analysis 直行)しているので、ダイアログを手で閉じれば確認可能。

## ハーネス TODO(別途)
- **JDK 導入**(Maestro 前提)or **ターミナルにアクセシビリティ権限付与**(cliclick/osascript でダイアログ自動消し)。これが無いと自動 UI QA は成立しない。
- 起動時に位置情報・通知を `simctl` で確実に事前許可する手順 / dev でこれらの prompt を抑止するガード。
- `harness-engineering/tools/native-qa.sh` を `EXPO_PUBLIC_DEV_AUTH_TOKEN` 自動ログイン方式に対応させる(openurl 確認ダイアログ回避)。
- Maestro 実行に JDK が要る点を README/前提に明記(or env-token + simctl screenshot のダイアログ非依存フローを既定化)。

## デプロイ手作業
- backend pull → `php artisan migrate`(pins.label)。owner が `feature/beginner-focus` を push。
- native は `feature/beginner-focus` を pull。
