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

## 関連(別途の残課題)
- backend `AppStoreService` は sandbox/production の**自動フォールバックが無い**(審査=sandbox購入で
  検証失敗のリスク)。`config('iap.environment')` 単一。→ production優先→失敗時sandbox再試行を推奨。
  **フォールバックを入れても本番でのSandbox試験は壊れない**(本番購入は1回目成功で発動せず、
  sandbox購入のみ再試行で通る)。本番常時ONは sandbox購入を本番が受理する=Apple推奨だが、
  ハードニングしたい場合はフラグで制御可。未実装(ユーザー判断待ち)。
