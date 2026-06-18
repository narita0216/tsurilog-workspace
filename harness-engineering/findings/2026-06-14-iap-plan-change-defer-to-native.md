# IAP: プラン変更/解約はアプリ内でやらず Apple純正の管理画面へ(2026-06-14)

## 症状
Sandbox で スタンダード→ライト の**ダウングレード**をすると、成功トーストは出る(Apple純正シート)のに、
- DB の `users.plan` が更新されない(「利用中」がスタンダードのまま)
- 購入ボタンが**永久にグルグル**する

## 原因(2つ)
1. **Apple 仕様**: 同一サブスクグループ内の**ダウングレードは次回更新まで遅延**。購入直後のアクティブ
   トランザクションはまだ上位プランなので、`/iap/verify` が返すのも上位プラン → DB は正しく据え置き。
   即時で下位に変わらないのは**バグではなく仕様**。アップグレードは即時反映される。
2. **コードのバグ**: `isPurchasing` を戻すのは `onPurchaseSuccess`/`onPurchaseError` の中だけ。
   ダウングレードは新トランザクションが流れず**コールバックが発火しない**ため、スピナーが戻らず固定。

## 対応(native `feature/ai-strategy`)
- 既存有料ユーザーの tier 変更・解約は**アプリ内で処理しない**。`deepLinkToSubscriptions()`
  (expo-iap、iOS は `apps.apple.com/account/subscriptions` を開く)で Apple 純正管理へ誘導。
  遅延反映や解約の案内は Apple の UI が正しく行う。
- アプリ内 `purchase()` は**新規購入(無料→有料)専用**に限定。
- スピナーを `isPurchasing:boolean` → `purchasingProductId:string|null`(ボタン単位)+ 保険タイムアウト化。
- 「購入を復元する」は **App Store 審査要件(Guideline 3.1.1)なので削除しない**。

## 教訓
- サブスクの**プラン変更/解約は Apple 純正の管理面に委ねる**のが定石。proration・遅延反映・
  解約フローを自前で再実装しない。アプリ内課金は「新規購入(コンバージョン)」に集中させる。
- `showManageSubscriptionsIOS` は expo-iap の単体 export に無い。**`deepLinkToSubscriptions` を使う**。
- 前提: ライト/スタンダードは**同一サブスクグループ**(別グループだと二重課金事故)。確認済み。

## 失効ガード(2026-06-14 対応済み `d21c2ef`)
`plan_expires_at` を利用時にチェックしておらず、失効通知(EXPIRED/REVOKE)の取りこぼしで
解約・期限切れ後も有料が使えていた。→ **`User::planKey()` に失効ガード**を追加(過去なら free、
staff除外)。planKey() 経由なので利用制限(AiUsageService)と表示(UserFormatterService)の
両方に一貫適用。DB downgrade は通知ハンドラのまま(非破壊の防御層)。テスト追加・276件緑。

## 環境フォールバック(2026-06-14 対応済み `8ba78a3`)
`AppStoreService::verifyTransaction` を「本番→失敗時sandbox再試行」にした(Apple推奨)。
本番設定のまま Sandbox/TestFlight/審査の購入も検証でき、審査リジェクトを防ぐ。
- `environments()`: production設定=[production, sandbox] / sandbox設定(開発)=[sandbox]のみ。
- Apple呼び出し+正規化を protected `fetchTransaction(env, txId)` に分離(`AppStoreServerAPI` は
  **final でモック不可**のため、ここを partial mock して単体テスト)。
- 落とし穴: **`Environment::PRODUCTION/SANDBOX` は型ではなく文字列定数**("Production"/"Sandbox")。
  コンストラクタ引数も string。型ヒントに `Environment` を使うと TypeError(try/catchに飲まれ全環境失敗)。
- 本番購入は1回目成功で再試行せず=**本番でのSandbox試験フロー(本番APIに向けて検証)を壊さない**。
- 注意: 本番が sandbox 取引も受理する(Apple推奨だが理論上の無課金プレミアム余地)。スケール上許容。
  ハードニングするなら environment フィールドでフラグ制御可能(未実装)。

## 失効の二層化(2026-06-14 `621bf12`)— 通知 + 再問い合わせ
失効ガード(`planKey` のローカル日付比較)単独だと、**通知V2の取りこぼしで「課金継続中なのにロックアウト」**する穴があった(自動更新で `plan_expires_at` を延ばすのは DID_RENEW 通知頼みのため)。対策として2層化:
1. **App Store Server Notifications V2(主・リアルタイム)**: 受け口 `/api/iap/app-store/notifications` は実装済み。ただし **ASC で通知URL(Production/Sandbox)の登録が必須**(=運用作業。未登録だと1通も来ない)。
2. **期限切れ時の Apple 再問い合わせ(保険)**: `AppStoreService::fetchSubscriptionStatus`(getAllSubscriptionStatuses + env フォールバック)→ `SubscriptionService::refreshIfExpired`。有効=期限延長 / 失効=free / 問い合わせ不能=猶予(`IAP_EXPIRY_RECHECK_GRACE_DAYS` 既定2日)で締め出さず再チェック。usage/現地/事前/追加質問の各コントローラ入口で実行。
- 設計原則: **不確実なときは課金中ユーザーを締め出さない方向に倒す**(Apple が「失効」と明言した時だけ free)。
- Sandbox の `plan_expires_at` が購入の数時間後など短い/不自然なのは Apple Sandbox(テスター更新レート設定)依存で、コードは Apple の値を保存しているだけ=バグではない。本番は実期間。

## 通知デコードのバグ(2026-06-17 `9a38a23`)— 最重要
本番ログで **全通知が `Notification is not a valid JSON array` で失敗**していた=**通知が一度も処理できていなかった**(失効/更新が DB に反映されない根本原因。「DB が実態とズレる」混乱の主犯)。
- 原因: readdle `ResponseBodyV2::createFromRawNotification($raw)` は **Apple が送る生の通知 JSON 全体**(`{"signedPayload":"<JWS>"}`)を期待し、内部で `json_decode` → `signedPayload` を取り出す。なのに我々は `$request->input('signedPayload')` で**取り出し済みの JWS 単体**を渡していた → JWS は JSON ではないので必ず失敗。
- 修正: `decodeNotification` で JWS を `json_encode(['signedPayload' => $jws])` に包んで渡す。
- 教訓: 通知が「来ない」ように見えても、まず**到達ログ**を見る(今回ログ追加で発覚)。署名付き JWS が要るためデコード成功の単体テストは作れず、本番ログ(エラー消失)で確認する。
- 併せて `fetchStatus`(getAllSubscriptionStatuses 解析)を「先頭取引」→「**アクティブ かつ 失効日時が最新**」採用に修正(汚れたアカウントで複数取引が並んでも tier 取り違えない)。

## Sandbox 試験の沼(まとめ)
- ASC の Sandbox テスター「前回の購入」欄は**当てにならない**(空でも Sandbox 不通の証拠にならない)。環境の最終判定は **verify ログの `environment`**(Apple が返す値)。
- 実機 + Settings→デベロッパ→Sandbox Account でも、**端末の StoreKit トランザクションキューに古い取引が残る**と起動時に再配信され DB を上書きする。クリーン化は**アプリ削除→再インストール**、それでもダメなら新テスター。
- 「ライト買って standard」は ASC 設定(group/level は正しい: Level1=Standard 最上位/Level2=Light)ではなく、**古い active standard 取引の再配信 or 通知デコード不能で失効が反映されない**ことが原因だった。

## plan_expires_at が過去のまま残る問題(2026-06-18 `2e3cadc`)
症状: DB の `plan_expires_at` が過去日のまま固定に見える。原因は**コードが過去値を書くのではなく**、
失効処理が**遅延型(AIエンドポイント叩いた時だけ refreshIfExpired)**で、DBを直接見る/AIを使わない
ケースでは誰も再評価せず、未来として書かれた値が時間経過で過去になっても放置されるため。
(applyVerifiedPurchase は過去 expires を free に落とすので、過去値が書かれること自体は無い)
対応:
- **`app:reconcile-subscriptions`(毎時30分)** を追加。期限切れの有料ユーザーを Apple へ再問い合わせ
  して plan を最新化(失効→free / 継続→延長 / 不能→猶予)。誰もアクセスしなくても DB が実態に追従。
- **grace バグ修正**: refreshIfExpired の active パスが applyVerifiedPurchase を呼んでいたため、
  Apple が active(課金リトライ/猶予)でも expires が過去だと誤って free に落ちていた。
  active なら維持し、read-time ガードで free 扱いされないよう未来側(猶予日数)へ寄せる。
- 注意: `original_transaction_id` を手で null にすると照合キーが無く reconcile も skip(据え置き)。
  実ユーザーは購入時にセットされるので問題ないが、手動テストで null にしないこと。

## ローカル環境メモ
- `readdle/app-store-server-api` は composer.lock にあるがコンテナ vendor に未インストールだった
  (テストが AppStoreService をモックするので顕在化せず)。`docker exec ... composer install` で同期。
