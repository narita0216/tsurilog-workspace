# 反省レポート: 課金(IAP)デバッグの長期化と私(AI)の失敗(2026-06-18)

数日にわたる課金まわりのデバッグで、私(AI)が判断を誤り、ユーザーを何度も無駄に消耗させた。
同じ失敗を繰り返さないための自己批判と、再発防止ルールを残す。

## 何が起きたか(要約)
- 単一の根本原因ではなく、**複数の別問題が重なって**「辻褄が合わない」状態が続いた:
  1. 通知デコードのバグ(JWS を生通知JSONに包まず渡していた → 全通知失敗)
  2. `plan_expires_at` を **UTC で保存**(`Carbon::createFromTimestampMs()` の TZ 既定が UTC)= **私のコードのバグ**
  3. **TestFlight と dev ビルド Sandbox の挙動差**(購入アカウント=本番Apple ID / 更新=日次×6週)を理解せず、5分更新・Sandboxテスター履歴を前提にしていた
  4. ユーザーが手動で `original_transaction_id` を null 化 → reconcile が据え置き
- これらを切り分けられず、私が**憶測で「コードの問題ではない」と早合点**したため、解決が大幅に遅れた。

## 私の失敗(率直に)
1. **外部要因に責任転嫁する早合点**。値がおかしいという報告に対し、検証前に「Apple の値だから」「Sandbox の仕様だから」と断定した。実際には **UTC保存は自分のバグ**だった。「絶対に過去で固定にならない」など**断定が強すぎた**(ユーザーの「Appleが過去日を返したら?」の指摘で前提の粗さが露呈)。
2. **テスト環境を最初に確定しなかった**。TestFlight なのか dev ビルド Sandbox なのかで「使われるアカウント」も「更新レート」も別物なのに、それを固める前にバックエンドのバグを疑い続けた。ユーザーに記事を提示されるまで TestFlight 仕様を調べなかった。
3. **記憶で外部プラットフォーム挙動を語った**。StoreKit / Sandbox / TestFlight の仕様を、公式ドキュメントやライブラリ実装を確認せずに断定した。
4. **タイムゾーンの基本を外した**。`Carbon::createFromTimestamp*()` は TZ 未指定だと UTC。外部の epoch を保存する時に app.timezone へ寄せていなかった。

## 再発防止ルール(チェックリスト化)

### A. タイムゾーン(コードの確定ルール)
- **外部の epoch / unix時刻 / ミリ秒を `Carbon` 化して保存する時は、必ず明示的に app.timezone(JST)へ寄せる。**
  - `Carbon::createFromTimestamp*()` / `createFromTimestampMs()` は **TZ 未指定だと UTC**。`->setTimezone(config('app.timezone'))` を付ける(良い例: `WorldTidesClient` は第2引数で 'Asia/Tokyo' を渡している)。
  - 保存先テーブルの他カラム(created_at 等は JST)と**表記を揃える**。絶対時刻は不変でも、混在は混乱と誤調査の元。
- 既定ルール → workspace CLAUDE.md §8.2 に明記した。

### B. 外部課金(IAP/サブスク)を調べる時は、まず「テスト環境」を確定する
- **TestFlight ≠ dev ビルド Sandbox ≠ 本番**。アカウントも更新レートも違う:
  - **TestFlight**: 購入は「設定→メディアと購入」の**本番 Apple ID**(デベロッパ設定のSandboxアカウントは無視)。更新は**24時間ごと・1週間で最大6回**。Sandboxアカウントを使うには先に本番IDをサインアウト。
  - **dev ビルド(`expo run:ios`)+ Sandboxアカウント**: デベロッパ設定の Sandbox アカウントを使用。更新は ASC 設定(既定5分・3/5/30/60分)・1日最大12回。**ライフサイクル検証はこちらが速い**。
- ASC の Sandbox テスター「前回の購入」欄は**当てにならない**(空でも不通の証拠にならない)。環境判定は **verify ログの `environment`**(Apple が返す値)。
- 出典: Apple「Testing subscriptions and In-App Purchases in TestFlight」/ Apple Developer Forums thread 770378 / RevenueCat docs。

### C. 「うちのバグではない」と言う前に、検証を挟む
- ユーザーがデータ異常を報告したら、**(1) 実コードを読む (2) 外部仕様を一次情報で確認する (3) ログで実値を見る** の最低3点を踏んでから結論する。憶測で外部要因に帰着させない。
- 「絶対〜にならない」のような**全称的な断定を避ける**。反例(例: Apple が過去日を返す)を自分で潰してから言う。

### D. 観測可能性を早く入れる
- 「届いているのか/何を返したか/どの分岐か」が分からない時は、**早期に warning ログ**を仕込む(本番 LOG_LEVEL が warning 想定なら info は見えない)。今回も通知受信ログ・refreshIfExpired 入口ログで一気に切り分いた。最初から入れるべきだった。

## 関連
- 課金実装の経緯・各修正 → `findings/2026-06-14-iap-plan-change-defer-to-native.md`
- ADR-0010(現地AI/課金)
