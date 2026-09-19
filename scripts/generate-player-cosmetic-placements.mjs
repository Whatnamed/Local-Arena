import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceRoot = resolve(root, "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/cosmetic_sources");
const botCatalogPath = resolve(sourceRoot, "cosmetic_catalog.json");
const botPlacementsPath = resolve(sourceRoot, "charm_placements.json");
const botAssetsPath = resolve(sourceRoot, "RandomizerAssets.cs.txt");
const panelPlacementsPath = resolve(root, "Panel/src/data/cosmeticPlacements.json");
const panelCharmsPath = resolve(root, "Panel/src/data/charmCatalog.json");
const panelAgentsPath = resolve(root, "Panel/src/data/agentCatalog.json");
const pluginCatalogPath = resolve(root, "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json");
const cosmeticApiCommit = "c3953dffc6b939b6df770c613741cc4e0f4cb2d0";
const cosmeticApiBase = `https://raw.githubusercontent.com/ByMykel/CSGO-API/${cosmeticApiCommit}/public/api/en`;
const cosmeticApiMirrorBase = `https://cdn.jsdelivr.net/gh/ByMykel/CSGO-API@${cosmeticApiCommit}/public/api/en`;

const catalog = JSON.parse(await readFile(botCatalogPath, "utf8"));
const nativePlacements = JSON.parse(await readFile(botPlacementsPath, "utf8"));
const botAssets = await readFile(botAssetsPath, "utf8");
const [keychainSource, agentSource] = await Promise.all([
  fetchJson("keychains.json", "keychain inventory images"),
  fetchJson("agents.json", "agent inventory images"),
]);

const stickerAnchors = (count) => Array.from({ length: count }, (_, schema) => {
  const x = count === 1 ? 0.5 : 0.25 + (schema / (count - 1)) * 0.5;
  const y = schema % 2 === 0 ? 0.48 : 0.42;
  return { schema, x: round(x), y };
});

function charmAnchors(positions) {
  if (!positions?.length) return [];
  const xs = positions.map((position) => position[0]);
  const zs = positions.map((position) => position[2]);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minZ = Math.min(...zs);
  const maxZ = Math.max(...zs);
  const spanX = Math.max(0.001, maxX - minX);
  const spanZ = Math.max(0.001, maxZ - minZ);
  const projected = positions.map((position, placementId) => ({
    placementId,
    x: round(0.2 + ((position[0] - minX) / spanX) * 0.6),
    y: round(0.7 - ((position[2] - minZ) / spanZ) * 0.4),
  }));
  const clustered = [];
  for (const candidate of projected) {
    if (clustered.every((entry) => Math.hypot(entry.x - candidate.x, entry.y - candidate.y) >= 0.075))
      clustered.push(candidate);
  }
  if (clustered.length <= 8) return clustered;
  return Array.from({ length: 8 }, (_, index) => clustered[Math.round(index * (clustered.length - 1) / 7)]);
}

const panel = {};
const pluginWeapons = {};
for (const weapon of [...catalog.weapons].sort((left, right) => left.defIndex - right.defIndex)) {
  const positions = nativePlacements[String(weapon.defIndex)] ?? [];
  panel[String(weapon.defIndex)] = {
    stickerSchemaCount: weapon.stickerSchemaCount,
    stickerPositions: stickerAnchors(weapon.stickerSchemaCount),
    charmPositions: charmAnchors(positions),
  };
  pluginWeapons[String(weapon.defIndex)] = {
    sticker_schema_count: weapon.stickerSchemaCount,
    charm_positions: positions.map((position, placementId) => ({
      placement_id: placementId,
      x: position[0],
      y: position[1],
      z: position[2],
    })),
  };
}

const charmIds = [...catalog.keychainDefinitions].sort((left, right) => left - right);
const keychainsById = new Map(keychainSource.rows.map((row) => [Number(row.def_index), row]));
const specialCharmNames = new Map([
  [36, "Austin 2025 Highlight Charm"],
  [37, "Sticker Display Case Charm"],
  [84, "Cologne 2026 Highlight Charm"],
]);
const charms = charmIds.map((id) => {
  const row = keychainsById.get(id);
  return {
    id,
    name: row?.name?.replace(/^Charm\s*\|\s*/i, "") || specialCharmNames.get(id) || `Charm #${id}`,
    image: inventoryImage(row),
  };
});
const agentModels = {
  ct: extractModels(botAssets, "CounterTerroristModels"),
  t: extractModels(botAssets, "TerroristModels"),
};
const agentsByModel = new Map(agentSource.rows.map((row) => [normalizeModel(row.model_player), row]));
const agents = Object.entries(agentModels).flatMap(([team, models]) =>
  models.map((model) => {
    const row = agentsByModel.get(model);
    return { team, model, name: row?.name || agentName(model), image: inventoryImage(row) };
  }));
const sourceHash = createHash("sha256")
  .update(await readFile(botCatalogPath))
  .update(await readFile(botPlacementsPath))
  .update(botAssets)
  .update(keychainSource.bytes)
  .update(agentSource.bytes)
  .digest("hex");
const plugin = {
  schema_version: 1,
  source_sha256: sourceHash,
  inventory_images: {
    repository: "ByMykel/CSGO-API",
    commit: cosmeticApiCommit,
    keychains_sha256: sha256(keychainSource.bytes),
    agents_sha256: sha256(agentSource.bytes),
  },
  charm_ids: charmIds,
  agent_models: agentModels,
  weapons: pluginWeapons,
};

await Promise.all([
  writeJson(panelPlacementsPath, panel),
  writeJson(panelCharmsPath, charms),
  writeJson(panelAgentsPath, agents),
  writeJson(pluginCatalogPath, plugin),
]);

console.log(`Generated ${Object.keys(panel).length} weapon capabilities, ${charms.length} charms, and ${agents.length} agents.`);

async function fetchJson(file, label) {
  let lastError;
  for (const base of [cosmeticApiBase, cosmeticApiMirrorBase]) {
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const response = await fetch(`${base}/${file}`, { signal: AbortSignal.timeout(30_000) });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const bytes = Buffer.from(await response.arrayBuffer());
        const rows = JSON.parse(bytes.toString("utf8"));
        if (!Array.isArray(rows)) throw new Error("response is not an array");
        return { rows, bytes };
      } catch (error) {
        lastError = error;
        if (attempt < 3) await new Promise((resolveDelay) => setTimeout(resolveDelay, attempt * 1000));
      }
    }
  }
  throw new Error(`Failed to fetch ${label}: ${lastError?.message ?? lastError}`);
}

function inventoryImage(row) {
  const image = typeof row?.image === "string" ? row.image.trim() : "";
  return image.startsWith("https://community.akamai.steamstatic.com/economy/image/") ? image : "";
}

function normalizeModel(model) {
  return typeof model === "string" ? model.replaceAll("/", "\\") : "";
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function extractModels(source, arrayName) {
  const match = source.match(new RegExp(`\\b${arrayName}\\s*=\\s*\\[(?<body>[\\s\\S]*?)\\n\\s*\\];`));
  if (!match?.groups?.body) throw new Error(`Could not locate ${arrayName} in RandomizerAssets.cs.txt`);
  const models = [...match.groups.body.matchAll(/"(agents\\\\models\\\\[^"\r\n]+\.vmdl)"/g)]
    .map((entry) => entry[1].replaceAll("\\\\", "\\"));
  if (!models.length || new Set(models).size !== models.length)
    throw new Error(`${arrayName} is empty or contains duplicate model paths`);
  return models;
}

function agentName(model) {
  const base = model.split("\\").at(-1).replace(/\.vmdl$/, "")
    .replace(/^(?:ctm|tm)_/, "")
    .replace(/_(?:variant|var)/, " ")
    .replaceAll("_", " ");
  return base.replace(/\b[a-z]/g, (letter) => letter.toUpperCase());
}

function round(value) {
  return Math.round(value * 10_000) / 10_000;
}

async function writeJson(path, value) {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
