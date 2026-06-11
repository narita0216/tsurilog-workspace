# Laravel Http(Guzzle)は URL 直書きクエリを query 配列で上書きする

## 事象
WorldTides 移行後、潮の動きが常に「不明」(tid_action null)になった。

`Http::get($url.'?extremes', $params)` のように**フラグパラメータを URL に直書き**すると、
Guzzle は `query` オプション(第2引数の配列)で **URL 側のクエリ文字列を丸ごと上書き**するため、
`extremes` が送信されない。WorldTides は extremes フラグ無しだと extremes 配列を返さず、
クライアントは「レスポンス不正」として空配列を返していた。

## 対策
値なしフラグは **query 配列に空値で含める**(`'extremes' => ''` → `extremes=` として送信)。
WorldTides は空値フラグを受理することを実キーで確認済み。

```php
// NG: ?extremes が消える
Http::get($url.'?extremes', ['lat' => $lat, ...]);
// OK
Http::get($url, ['extremes' => '', 'lat' => $lat, ...]);
```

## 教訓
- 外部 API クライアントは **Http::fake のテストだけでは検出できない**(fake はワイルドカード
  `api/v3*` でマッチするため、クエリが欠けていても緑になる)。実キーでの疎通確認を 1 回挟む。
- 同時に発覚した既存バグ: 下げ局面の「下げ3分/下げ7分」判定が WWO 時代から逆だった
  (満潮直後に下げ7分を返していた)。`0bdfa25` で仕様(満潮→下げ3分→下げ7分→干潮)に統一。

関連: `findings/2026-06-12-handoff-tide-api-migration.md`
