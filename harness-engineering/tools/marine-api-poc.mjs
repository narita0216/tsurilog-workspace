#!/usr/bin/env node
/**
 * marine-api-poc.mjs — 波高/海象 API の横並び比較 PoC
 *
 * AI戦略機能(initiatives/ai-strategy-feature.md)で「波高/うねり/海面水温/潮汐」を
 * どの海象 API から取るか決めるための実測ツール。同じ釣り場・同じ時刻で
 * Open-Meteo / WWO / Stormglass を叩き、取れる項目と値を並べて比較する。
 *
 * 海しる(MSIL)は水深/地形/潮汐/水温の本命(別経路・要登録キー)。本 PoC は
 * 海しるに無い「波高」を補う海象 API の選定に絞る(assessment/external-apis-ai-strategy.md)。
 *
 * 使い方:
 *   node harness-engineering/tools/marine-api-poc.mjs [lat] [lng]
 *   # 例(和歌山・串本沖がデフォルト):
 *   node harness-engineering/tools/marine-api-poc.mjs 33.47 135.78
 *
 * キー(任意・env で渡す。無ければそのソースはスキップ):
 *   WWO_API_KEY=...          # https://www.worldweatheronline.com/ で無料登録
 *   STORMGLASS_API_KEY=...   # https://stormglass.io/ で無料登録
 *   # Open-Meteo はキー不要(評価用。本番商用はライセンス要確認)
 *
 * 要 Node 18+(global fetch)。
 */

const lat = parseFloat(process.argv[2] ?? "33.47");
const lng = parseFloat(process.argv[3] ?? "135.78");

const fmt = (v, suffix = "") =>
  v === undefined || v === null || Number.isNaN(v) ? "—" : `${v}${suffix}`;

async function openMeteo() {
  const url =
    `https://marine-api.open-meteo.com/v1/marine?latitude=${lat}&longitude=${lng}` +
    `&hourly=wave_height,swell_wave_height,wave_period,wave_direction,sea_surface_temperature` +
    `&timezone=Asia%2FTokyo&forecast_days=1`;
  const r = await fetch(url);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const j = await r.json();
  const h = j.hourly;
  const i = 0; // 先頭の時刻
  return {
    source: "Open-Meteo",
    waveHeight: h?.wave_height?.[i],
    swellHeight: h?.swell_wave_height?.[i],
    wavePeriod: h?.wave_period?.[i],
    waveDir: h?.wave_direction?.[i],
    waterTemp: h?.sea_surface_temperature?.[i],
    tide: "（tide は別 API。Open-Meteo は潮汐なし）",
    note: "キー不要。本番商用はライセンス要確認",
  };
}

async function wwo() {
  const key = process.env.WWO_API_KEY;
  if (!key) return { source: "WWO", skipped: "WWO_API_KEY 未設定" };
  const url =
    `https://api.worldweatheronline.com/premium/v1/marine.ashx?key=${key}` +
    `&q=${lat},${lng}&format=json&tide=yes&tp=1`;
  const r = await fetch(url);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const j = await r.json();
  const w = j?.data?.weather?.[0];
  const hr = w?.hourly?.[0];
  const tide = w?.tides?.[0]?.tide_data?.[0];
  return {
    source: "WWO",
    waveHeight: hr ? parseFloat(hr.sigHeight_m) : undefined,
    swellHeight: hr ? parseFloat(hr.swellHeight_m) : undefined,
    wavePeriod: hr ? parseFloat(hr.swellPeriod_secs) : undefined,
    waveDir: hr ? parseFloat(hr.swellDir) : undefined,
    waterTemp: hr ? parseFloat(hr.waterTemp_C) : undefined,
    tide: tide ? `${tide.tide_type} ${tide.tideTime} (${tide.tideHeight_mt}m)` : "—",
    note: "有料(無料枠あり)。潮汐・水温・波を 1 ソースで網羅",
  };
}

async function stormglass() {
  const key = process.env.STORMGLASS_API_KEY;
  if (!key) return { source: "Stormglass", skipped: "STORMGLASS_API_KEY 未設定" };
  const params = "waveHeight,swellHeight,wavePeriod,waveDirection,waterTemperature";
  const url = `https://api.stormglass.io/v2/weather/point?lat=${lat}&lng=${lng}&params=${params}`;
  const r = await fetch(url, { headers: { Authorization: key } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const j = await r.json();
  const p = j?.hours?.[0];
  const pick = (o) => (o ? (o.sg ?? Object.values(o)[0]) : undefined);
  // 潮汐は別エンドポイント
  let tide = "—";
  try {
    const tr = await fetch(
      `https://api.stormglass.io/v2/tide/extremes/point?lat=${lat}&lng=${lng}`,
      { headers: { Authorization: key } },
    );
    if (tr.ok) {
      const tj = await tr.json();
      const t = tj?.data?.[0];
      if (t) tide = `${t.type} ${t.time} (${t.height}m)`;
    }
  } catch {
    /* tide 取得失敗は致命的でない */
  }
  return {
    source: "Stormglass",
    waveHeight: pick(p?.waveHeight),
    swellHeight: pick(p?.swellHeight),
    wavePeriod: pick(p?.wavePeriod),
    waveDir: pick(p?.waveDirection),
    waterTemp: pick(p?.waterTemperature),
    tide,
    note: "本番は有料。波・水温・潮汐を統合",
  };
}

async function main() {
  console.log(`\n釣り場: lat=${lat}, lng=${lng}（先頭時刻の値で比較）\n`);
  const results = await Promise.allSettled([openMeteo(), wwo(), stormglass()]);

  const rows = results.map((res, idx) => {
    const name = ["Open-Meteo", "WWO", "Stormglass"][idx];
    if (res.status === "rejected")
      return { source: name, error: String(res.reason?.message ?? res.reason) };
    return res.value;
  });

  for (const r of rows) {
    console.log("────────────────────────────────────────");
    console.log(`■ ${r.source}`);
    if (r.skipped) {
      console.log(`  skip: ${r.skipped}`);
      continue;
    }
    if (r.error) {
      console.log(`  error: ${r.error}`);
      continue;
    }
    console.log(`  波高     : ${fmt(r.waveHeight, " m")}`);
    console.log(`  うねり   : ${fmt(r.swellHeight, " m")}`);
    console.log(`  周期     : ${fmt(r.wavePeriod, " s")}`);
    console.log(`  向き     : ${fmt(r.waveDir, " °")}`);
    console.log(`  海面水温 : ${fmt(r.waterTemp, " ℃")}`);
    console.log(`  潮汐     : ${r.tide ?? "—"}`);
    if (r.note) console.log(`  メモ     : ${r.note}`);
  }
  console.log("────────────────────────────────────────");
  console.log(
    "\n比較観点: 日本沿岸の値の妥当性 / 潮汐の有無と精度 / レート制限・料金 / レスポンスの扱いやすさ。",
  );
  console.log("詳細: harness-engineering/assessment/external-apis-ai-strategy.md\n");
}

main().catch((e) => {
  console.error("PoC 実行エラー:", e);
  process.exit(1);
});
