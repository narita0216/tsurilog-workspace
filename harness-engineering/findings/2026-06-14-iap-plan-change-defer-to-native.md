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

## 関連(別途の残課題・要対応)
- backend `AppStoreService` は sandbox/production の**自動フォールバックが無い**(審査=sandbox購入で
  検証失敗のリスク)。`config('iap.environment')` 単一。→ production優先→失敗時sandbox再試行を推奨。
- `plan_expires_at` を**利用時にチェックしていない**(失効は通知V2頼み・定期ジョブ無し)。
  通知欠落時に有料が残る穴。読み取り時の失効ガードを推奨。
