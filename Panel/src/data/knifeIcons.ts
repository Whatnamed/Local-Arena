import skins from "./skinImages.json";
import { compareKnifeTypes } from "./cosmeticOrder";

const compareKnifeIds = (a: number, b: number) => compareKnifeTypes({ id: a }, { id: b });

export type KnifeIcon = { id: number; url: string };

const KNIFE_IDS = [500, 503, 505, 506, 507, 508, 509, 512, 514, 515, 516,
  517, 518, 519, 520, 521, 522, 523, 525, 526];

type SkinRow = {
  weapon_defindex: number;
  paint: number | string;
  image: string;
};

const rows = skins as SkinRow[];

/** Ordered by the product's knife preference; the full catalog stays intact. */
export const KNIFE_ICONS: KnifeIcon[] = [...KNIFE_IDS].sort(compareKnifeIds).map(
  (id) => {
    const base = rows.find(
      (row) => Number(row.weapon_defindex) === id && Number(row.paint) === 0
    );
    return { id, url: base?.image ?? "" };
  }
);
