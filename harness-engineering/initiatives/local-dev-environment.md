# Initiative: ローカル開発環境(backend Docker / native dev client)

- **Status:** 🟡 進行中
- **Owner:** [TBD]
- **Date started:** 2026-05-28
- **Related:** ADR-0003

## なぜやるか(目的)

動作検証はローカルで完結させる方針(ADR-0003)。そのためには backend(Docker Compose)と native(Expo dev client)が誰でも確実に立ち上がる必要がある。立ち上げ手順と落とし穴を整備し、新規メンバーが 30 分で開発開始できる状態にする。

## ゴール / 完了条件

- [ ] `docker compose up -d` → `migrate --seed` → `curl localhost:8080/api/` が通る手順を確定
- [ ] `queue` / `scheduler` コンテナの役割と確認方法を文書化(push / 定期バッチ)
- [ ] native: dev client ビルド → `npx expo start --dev-client` → 実機接続の手順を確定
- [ ] `.env`(backend / native)の最小設定例を整備
- [ ] 各リポ README に追記、落とし穴は findings に蓄積

## 進め方(計画)

1. backend: `docker-compose.yml`(api/queue/scheduler/db)と `docker-compose-local.yml` の差を確認し、ローカル推奨を決める。
2. backend: `.env.example` の DB 設定(現状 `DB_DATABASE=laravel` 等)を compose の `tsurilog` / `tsurilog_user` / `5432` に合わせる手順を明記。
3. backend: マイグレーション + マスタ seeder の投入を追試。
4. native: EAS dev client(`eas build --profile development`)→ 実機インストール → `EXPO_PUBLIC_API_DOMAIN` をローカル backend に向ける手順を追試。
5. 判明した手順・ハマりを README / findings に反映。

## 進捗ログ

- **2026-05-28:** 構成把握。backend は Docker Compose(api/queue/scheduler/db=postgres16)、native は dev client 前提(Expo Go 不可)。`docker-compose.yml` の DB password と `.env.example`(DB_DATABASE=laravel)に差異あり → 統一手順が要る。

## 落とし穴・メモ

- `.env.example` の `DB_DATABASE=laravel` / `DB_USERNAME=root` は compose の `tsurilog` / `tsurilog_user` と食い違う。ローカルでは compose 側に合わせる。
- `docker compose down -v` は DB ボリュームを消すため禁止(deny 済み)。データを保ったまま再起動は `down`(`-v` なし)。
- native の `EXPO_PUBLIC_API_DOMAIN` は実機から見える backend のアドレス(同一 Wi-Fi なら開発機の LAN IP:8080)。`localhost` は実機からは届かない点に注意。
