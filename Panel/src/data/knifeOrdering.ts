// Knife model ordering and finish sort policy per docs/PRODUCT-SCOPE.md.

export const DEFAULT_KNIFE_ORDER = [
  507, // Karambit (爪子刀)
  515, // Butterfly Knife (蝴蝶刀)
  508, // M9 Bayonet (M9 刺刀)
  500, // Bayonet (刺刀)
  525, // Skeleton Knife (骷髅匕首)
  512, // Falchion Knife (弯刀)
  523, // Talon Knife (锯齿爪刀)
  503, // Classic Knife (海豹短刀)
  505, // Flip Knife (折叠刀)
  509, // Huntsman Knife (猎杀者匕首)
  522, // Stiletto Knife (短剑)
  521, // Nomad Knife (流浪者匕首)
  519, // Ursus Knife (熊刀)
  517, // Paracord Knife (系绳匕首)
  518, // Survival Knife (求生匕首)
  526, // Kukri Knife (廓尔喀刀)
  514, // Bowie Knife (鲍伊猎刀)
  506, // Gut Knife (穿肠刀)
  516, // Shadow Daggers (暗影双匕)
  520, // Navaja Knife (折刀)
];

// Dark / neutral / classic finish preference scores.
// Catalog compatibility is 100% preserved; this priority only governs display sorting.
const FINISH_PRIORITY: Record<number, number> = {
  // Dark / neutral finishes
  42: 100,  // Blue Steel (蓝钢)
  40: 95,   // Night (夜色)
  1436: 95, // Night Stripe (极夜之霜)
  98: 90,   // Ultraviolet (紫外线)
  417: 88,  // Doppler Black Pearl (黑珍珠)
  617: 88,  // Gamma Doppler Black Pearl
  858: 88,  // Black Pearl
  410: 85,  // Damascus Steel (大马士革钢)
  43: 80,   // Stained (斑驳)
  143: 75,  // Urban Masked (城市迷彩)
  323: 70,  // Rust Coat (锈蚀)
  175: 65,  // Scorched (焦枯)
  5: 60,    // Forest DDPAT (森林 DDPAT)
  // Popular classics
  44: 55,   // Case Hardened (表面淬火)
  12: 52,   // Crimson Web (深红之网)
  38: 50,   // Fade (渐变之色)
  415: 48,  // Doppler Ruby (红宝石)
  416: 48,  // Doppler Sapphire (蓝宝石)
  568: 48,  // Gamma Doppler Emerald (绿宝石)
  413: 45,  // Marble Fade (渐变大理石)
  409: 40,  // Tiger Tooth (虎牙)
  561: 38,  // Lore (传说)
  562: 38,  // Autotronic (自动解析)
};

export function getKnifeFinishPriority(paint: number): number {
  return FINISH_PRIORITY[paint] ?? 0;
}

export function sortKnifeSkins<T extends { paint: number }>(skins: T[]): T[] {
  return [...skins].sort((a, b) => {
    const prioA = getKnifeFinishPriority(a.paint);
    const prioB = getKnifeFinishPriority(b.paint);
    if (prioA !== prioB) {
      return prioB - prioA; // Higher priority first
    }
    return a.paint - b.paint;
  });
}
