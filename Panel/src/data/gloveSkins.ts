import namesZh from "./gloveNames.zh-CN.json";

export type GloveSkin = {
  defindex: number;
  model: string;
  paint: number;
  name: string;
  image: string;
  minWear: number;
  maxWear: number;
};

const GLOVE_NAMES_ZH = namesZh as Record<string, string>;

const GLOVE_MODEL_NAMES: Record<number, { english: string; schinese: string; tchinese: string }> = {
  4725: { english: "Broken Fang Gloves", schinese: "狂牙手套", tchinese: "狂牙手套" },
  5027: { english: "Bloodhound Gloves", schinese: "血猎手套", tchinese: "血獵手套" },
  5030: { english: "Sport Gloves", schinese: "运动手套", tchinese: "運動手套" },
  5031: { english: "Driver Gloves", schinese: "驾驶手套", tchinese: "駕駛手套" },
  5032: { english: "Hand Wraps", schinese: "裹手", tchinese: "裹手" },
  5033: { english: "Moto Gloves", schinese: "摩托手套", tchinese: "摩托手套" },
  5034: { english: "Specialist Gloves", schinese: "专业手套", tchinese: "專業手套" },
  5035: { english: "Hydra Gloves", schinese: "九头蛇手套", tchinese: "九頭蛇手套" },
};

export function gloveModelName(language: string | null | undefined, defindex: number): string {
  const names = GLOVE_MODEL_NAMES[defindex];
  if (!names) return `#${defindex}`;
  return language === "schinese" ? names.schinese : language === "tchinese" ? names.tchinese : names.english;
}

export function gloveSkinName(language: string | null | undefined, skin: GloveSkin): string {
  return language === "schinese" ? GLOVE_NAMES_ZH[`${skin.defindex}:${skin.paint}`] ?? skin.name : skin.name;
}

export function matchesGloveSearch(skin: GloveSkin, query: string): boolean {
  const text = [skin.model, skin.name, skin.paint, skin.defindex,
    gloveModelName("english", skin.defindex), gloveModelName("schinese", skin.defindex),
    gloveModelName("tchinese", skin.defindex), gloveSkinName("schinese", skin)].join(" ").toLowerCase();
  return query.trim().toLowerCase().split(/\s+/).every((word) => text.includes(word));
}

export { default } from "./gloveSkins.json";
