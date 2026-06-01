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
- **2026-05-29:** backend をローカルで起動しテスト実行成功(下記手順を確立)。**phpunit: 181 tests / 177 pass / 4 error**(4件は GD 拡張未導入のみ)。`OpenMeteoClient`(BE-1)を tinker で実 Open-Meteo 疎通確認OK。

## backend ローカル起動手順(確認済み 2026-05-29)

```bash
# 1. .env を作成(.env.example ベース。DB を compose に合わせる)
#    DB_HOST=db / DB_DATABASE=tsurilog / DB_USERNAME=tsurilog_user / DB_PASSWORD=your_secure_password
# 2. ★ローカルは docker-compose-local.yml を使う(.:/var/www を bind mount)
docker compose -f docker-compose-local.yml up -d api db
# 3. 依存と鍵(コンテナ内)
docker compose -f docker-compose-local.yml exec api sh -lc 'COMPOSER_MEMORY_LIMIT=-1 composer install'
docker compose -f docker-compose-local.yml exec api php artisan key:generate --force
docker compose -f docker-compose-local.yml exec api php artisan migrate --seed --force
# 4. テスト(sqlite :memory:)
docker compose -f docker-compose-local.yml exec api ./vendor/bin/phpunit   # ← artisan test は未定義
```

## 落とし穴・メモ

- `.env.example` の `DB_DATABASE=laravel` / `DB_USERNAME=root` は compose の `tsurilog` / `tsurilog_user` と食い違う。ローカルでは compose 側に合わせる。
- `docker compose down -v` は DB ボリュームを消すため禁止(deny 済み)。データを保ったまま再起動は `down`(`-v` なし)。
- native の `EXPO_PUBLIC_API_DOMAIN` は実機から見える backend のアドレス(同一 Wi-Fi なら開発機の LAN IP:8080)。`localhost` は実機からは届かない点に注意。
- **クローン直後に `.env` が無いと、起動時に `Client Id property iosClientId must be defined to use Google auth` で全画面クラッシュする**(`use-auth.ts` が `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID` を読み、未定義だと `Google.useAuthRequest` が throw → 全画面ラッパ `LoggedInLayout` で落ちる)。原因が分かりにくい。先に native README §3 の通り `.env`(`EXPO_PUBLIC_API_DOMAIN` / `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID` / `EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID`)を作る。`EXPO_PUBLIC_*` は Metro がバンドル時に埋め込むため、`.env` 作成後は dev server 再起動(`npx expo start -c`)で反映 = ネイティブ再ビルド不要。
- **カメラは無効化されている**(app.json の expo-image-picker `cameraPermission: false`)。`launchCameraAsync` は "Missing camera permission" で落ちる。写真/動画はライブラリ選択(`launchImageLibraryAsync`)のみ可。カメラを使う機能は `cameraPermission` 有効化 + dev client 再ビルドが要る。
- **(backend)`docker-compose.yml`(本番相当)はコードを COPY する**ため、稼働中コンテナにローカルの新規/編集ファイルが反映されない。ローカル開発は必ず `docker-compose-local.yml`(`.:/var/www` bind mount)で起動する。
- **(backend)`composer install` が exit 137(OOM)で kill される**ことがある → `COMPOSER_MEMORY_LIMIT=-1` を付ける。
- **(backend)ローカル Docker イメージに GD 拡張が無い** → 画像アップロード系テスト4件が `GD extension is not installed` で error。`local_docker/Dockerfile` に `gd` を追加してビルドすれば解消(要イメージ再ビルド)。
- **(backend)永続 DB ボリュームに古い部分スキーマが残ると `migrate` が失敗**する(例: `remove_unique_from_logs_record_datetime` が実在しない制約 `logs_record_datetime_unique` を drop しようとする。実DBの制約は `logs_record_datetime_hour_unique`)。fresh/sqlite では通るので**テストには影響なし**。`migrate:fresh` は deny のため、dev DB を作り直す場合は手動対応。
- **`php artisan test` は未定義**。`./vendor/bin/phpunit` を使う。
