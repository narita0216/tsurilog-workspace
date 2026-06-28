# 2026-06-28 釣果カードUI刷新で踏んだ2点(RNモーダル多重 / null環境データでクラッシュ)

1.1.4 釣果記録のUIをリリース品質へ仕上げる過程(シミュレータQA)で踏んだ落とし穴。

## 1. RN の Modal はモーダルの上にモーダルを重ねられない(iOS)

図鑑 → 魚種タップ → 魚種カード一覧(`SpeciesCardsModal`=Modal)→ カードタップで
拡大・共有(`CatchCardModal`=Modal)という二段モーダルにしたら、**2枚目の Modal が
出ない**(タップは成功するが画面が変わらない)。React Native の `Modal` は同一フレームで
別 Modal を上に提示できないため(iOS の presentation 制約)。

**対処:** 2枚目のモーダルをやめ、`SpeciesCardsModal` の各カードに `ViewShot` と共有ボタンを
直付けして**その場で共有完結**にした(UX的にもむしろ良い)。`CatchCardModal` は単独で開く
箇所(釣行記録詳細)では問題なく動く=「Modal の上に Modal」だけが地雷。

教訓: モーダルの中からさらにモーダルを開く導線は避け、インラインのオーバーレイ/シート、
または1枚目を閉じてから開く設計にする。

## 2. 環境データ null で記録詳細がクラッシュ(`.toString of null`)

`my-records/[id].tsx` が `log.temperature.toString()` / `log.water_temperature.toString()` /
`log.caught_fish_size.toString()` を**無防備に呼んでいて**、env が null の釣果でレンダーエラー
(`Cannot read property 'toString' of null`)。実釣果は `GetEnvData` で env が埋まるため通常は
顕在化しないが、env 無しデータ(QAシード/取得失敗/古いデータ)で確実に落ちる。

**対処:** 各バッジを「値があるときだけ表示」に変更(null は非表示)。`.toString()` をやめ
テンプレートリテラル + null ガードに。崩れも「null」表示も同時に解消。

教訓: API由来の数値/文字列を画面で直に `.toString()` しない。null 安全を既定に。

## QA メモ(再現環境)
- ローカル Docker API(`localhost:8080`)に向けて native を `EXPO_PUBLIC_API_DOMAIN` 上書き +
  `EXPO_PUBLIC_DEV_AUTH_TOKEN` でQAユーザ自動ログイン。検証後 `.env` は復元。
- Maestro のタブ/タイルのタップは**テキストが取れない**ことがあり、`maestro hierarchy` で
  bounds を見て**ポイント割合(例: 図鑑タブ=70%,93%)**で叩くのが確実。JDK は
  `/usr/local/opt/openjdk`(`JAVA_HOME` 要設定)。
