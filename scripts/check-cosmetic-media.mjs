import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const panelData = path.join(repo, "Panel", "src", "data");
const remote = process.argv.includes("--remote");

async function json(name) {
  return JSON.parse(await readFile(path.join(panelData, name), "utf8"));
}

function imageUrl(value, label) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${label}: image is empty`);
  const url = new URL(value);
  if (!/^https?:$/.test(url.protocol)) throw new Error(`${label}: image must use HTTP(S)`);
  return url.toString();
}

const gloves = await json("gloveSkins.json");
const gloveNames = await json("gloveNames.zh-CN.json");
const music = await json("musicKits.json");
const skinImages = await json("skinImages.json");

const urls = new Set();
for (const row of gloves) {
  const key = `${row.defindex}:${row.paint}`;
  urls.add(imageUrl(row.image, `glove ${key}`));
  if (!gloveNames[key]) throw new Error(`glove ${key}: missing Simplified Chinese name`);
}
for (const row of music) {
  if (!row.name_en || !row.name_zh) throw new Error(`music ${row.def_index}: missing localized name`);
  urls.add(imageUrl(row.image, `music ${row.def_index}`));
}
for (const row of skinImages) urls.add(imageUrl(row.image, `skin ${row.weapon_defindex}:${row.paint}`));

console.log(`Cosmetic media schema OK: gloves=${gloves.length}, music=${music.length}, skinImages=${skinImages.length}, uniqueUrls=${urls.size}`);
if (!remote) process.exit(0);

const queue = [...urls];
const failures = [];
let checked = 0;
const workers = Array.from({ length: 24 }, async () => {
  while (queue.length) {
    const url = queue.pop();
    if (!url) return;
    let status = 0;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 15000);
      let response = await fetch(url, { method: "HEAD", signal: controller.signal });
      clearTimeout(timer);
      if (response.status === 405 || response.status === 403) {
        const fallbackController = new AbortController();
        const fallbackTimer = setTimeout(() => fallbackController.abort(), 15000);
        response = await fetch(url, { headers: { Range: "bytes=0-0" }, signal: fallbackController.signal });
        clearTimeout(fallbackTimer);
      }
      status = response.status;
      if (!response.ok) failures.push({ url, status });
    } catch (error) {
      failures.push({ url, status, error: error instanceof Error ? error.message : String(error) });
    }
    checked++;
    if (checked % 100 === 0 || checked === urls.size) console.log(`Remote media check: ${checked}/${urls.size}`);
  }
});
await Promise.all(workers);
if (failures.length) {
  console.error(`Remote media check failed: ${failures.length}/${urls.size}`);
  for (const failure of failures.slice(0, 20)) console.error(JSON.stringify(failure));
  process.exit(1);
}
console.log(`Remote media check OK: ${urls.size}/${urls.size}`);
