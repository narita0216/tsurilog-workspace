# Laravel `Http::fake()` は「最初に登録したスタブ」が勝つ(setUp 上書き不可)

- 日付: 2026-06-08
- 文脈: AIアドバイザー現地(ADR-0010 S3)の結合テスト追加時にハマった。

## 症状

`CreateStrategyEndpointTest::setUp()` で `Http::fake(['https://api.anthropic.com/*' => ...])`
を登録済みのところに、個別テスト内で同じ URL パターンを `Http::fake()` で再登録して
**レスポンスを上書きしたつもり**が効かず、テストは setUp 側の JSON を受け取り続けた。
結果、現地用キー(`onsite_delta`/`local_summary`)を含まない応答になり、
`OnSiteScoreService::compose` が `hasAi=false` → 固定重みの `evaluate()` フォールバックに落ちて、
`delta` が config シグナルの重み合計(例: 潮目6+鳥山8=14)になっていた。

## 原因

`Http::fake()` は呼ぶたびにスタブを**マージ(追記)**する。リクエストが複数パターンに
マッチする場合、**先に登録されたスタブが優先**される。`setUp()` は個別テストより先に
走るため、テスト内の後追い `Http::fake()` では同一 URL を上書きできない。

## 対処(採用)

setUp 側のスタブを**クロージャ**にして、リクエスト内容で返す JSON を切り替える。

```php
'https://api.anthropic.com/*' => function ($request) use ($preTripJson, $onSiteJson) {
    $content = $request->data()['messages'][0]['content'] ?? '';
    $isOnSite = is_string($content) && str_contains($content, '現場の観察');
    return Http::response([
        'content' => [['type' => 'text', 'text' => $isOnSite ? $onSiteJson : $preTripJson]],
        'usage'   => [...],
    ], 200);
},
```

プロンプト本文(最初の user メッセージ)に現地ヒヤリングの目印
(`# 現場の観察`)が含まれるかで分岐。実挙動(現地のときだけ AI が現地キーを返す)を
そのまま再現でき、既存テスト(観察なし)も従来どおり pre-trip JSON を受ける。

## 教訓

- テスト内で「特定の1ケースだけ別レスポンス」にしたい時、`Http::fake()` の後追い登録に頼らない。
  setUp のスタブを**リクエスト依存のクロージャ**にするのが確実。
- 値が固定重みの和にピタリ一致したら「フォールバック経路を踏んでいる」サイン。
  AI 判断経路(`hasAi`)が期待通り通っているか、入力(delta/summary)が空でないかを疑う。
- system プロンプトで分岐したい場合は `$request->data()['system'][0]['text']` を見る。

関連: ADR-0010(現地アドバイザー)、`OnSiteScoreService::compose`/`evaluate`。
