# native スタイリング: CLAUDE.md は NativeWind 指定だが実コードは 100% StyleSheet

- **Date:** 2026-05-29
- **Repo:** tsurilog-native
- **Tags:** native, styling, harness-drift

## 何が起きているか

CLAUDE.md §8.3 は「スタイルは **NativeWind(className)**。新規の生 StyleSheet を増やさない」と規定している。
しかし実コードを計測すると **`className` の使用は 0 件 / `StyleSheet.create` は 46 ファイル**。
全画面・全コンポーネントが StyleSheet + ダークテーマ(`constants/config` の `MAIN_COLOR` /
`APPLICATION_BACKGROUND_COLOR` / `APPLICATION_TEXT_COLOR` 等、`#333` 系)で書かれている。

NativeWind 自体は導入・設定済み(`package.json` の `nativewind@^4.2.1` / `global.css` /
`tailwind.config.js` / `babel.config.js` の `nativewind/babel` preset)だが、**一度も使われていない**。

## なぜ重要か

- 新規 UI を書くとき「CLAUDE.md に従う(NativeWind)」と「周囲のコードに合わせる(StyleSheet)」が真っ向から矛盾する。
- NativeWind で新規画面を書くと、既存 46 ファイルと見た目の実装様式が断絶し、一貫性を損なう。
- §8.3 を信じた AI/人が NativeWind で書き始めると、レビューで差し戻し・二重メンテになる。

## 決定(2026-05-29)

**A. 実態追認を採用。** 新規 UI も既存に合わせて `StyleSheet.create` + `constants/config` のダークテーマで書く。
CLAUDE.md §8.3 を「StyleSheet で統一(NativeWind は導入済みだが未使用)」に修正済み。
NativeWind 採用に切り替えるなら別途 ADR を起こす。

## 関連
- CLAUDE.md §8.3
- イニシアチブ: `initiatives/ai-strategy-feature.md`
