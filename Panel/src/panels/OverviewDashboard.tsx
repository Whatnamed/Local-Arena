import { useEffect, useState } from "react";
import {
  ArrowRight,
  BookOpenText,
  Crosshair,
  Download,
  Settings2,
  Sticker,
  type LucideIcon,
} from "lucide-react";
import StatusBar from "../components/StatusBar";
import ModeCard from "./ModeCard";
import { api, type OnlineUpdateSnapshot } from "../lib/api";
import { useStore } from "../state/store";
import { useT, type I18nKey } from "../i18n";
import { stickerFeatureEnabled } from "../lib/stickerEditor";

export type DashboardTarget = "weaponPresets" | "stickers" | "guide" | "settings";

type Tile = { view: DashboardTarget; key: I18nKey; icon: LucideIcon };

export default function OverviewDashboard({ onNavigate }: { onNavigate: (view: DashboardTarget) => void }) {
  const t = useT();
  const { config } = useStore();
  const [updates, setUpdates] = useState<OnlineUpdateSnapshot | null>(null);
  const stickersVisible = stickerFeatureEnabled(config);

  useEffect(() => {
    void api.getUpdateSnapshot().then(setUpdates).catch(() => {});
  }, []);

  const updateAvailable = !!updates && (updates.panel.update_available || updates.plugin.update_available);

  const tiles: Tile[] = [
    { view: "weaponPresets", key: "weapons.title", icon: Crosshair },
    ...(stickersVisible ? [{ view: "stickers" as DashboardTarget, key: "stickers.title" as I18nKey, icon: Sticker }] : []),
    { view: "guide", key: "nav.guide", icon: BookOpenText },
    { view: "settings", key: "set.title", icon: Settings2 },
  ];

  return (
    <div className="dashboard">
      <header className="workspace__head">
        <span className="workspace__eyebrow">Local Arena</span>
        <h1>{t("nav.overview")}</h1>
      </header>
      <StatusBar onOpenSettings={() => onNavigate("settings")} />

      {updateAvailable && (
        <button className="update-banner" onClick={() => onNavigate("settings")}>
          <span className="update-banner__icon" aria-hidden="true"><Download size={17} /></span>
          <strong>{t("update.available")}</strong>
          <small>{updates.release_version ? `v${updates.release_version}` : ""}</small>
          <span className="update-banner__action">
            {t("set.updates")}
            <ArrowRight size={14} />
          </span>
        </button>
      )}

      <div className="dashboard__controls">
        <ModeCard />
      </div>

      <div className="quick-grid" role="navigation" aria-label={t("overview.quickActions")}>
        {tiles.map(({ view, key, icon: Icon }) => (
          <button key={view} className="quick-tile" onClick={() => onNavigate(view)}>
            <Icon size={18} strokeWidth={1.9} aria-hidden="true" />
            <span>{t(key)}</span>
          </button>
        ))}
      </div>

      <button className="tutorial-card glass" onClick={() => onNavigate("guide")}>
        <span className="tutorial-card__icon" aria-hidden="true">
          <BookOpenText size={22} strokeWidth={1.8} />
        </span>
        <span className="tutorial-card__body">
          <small>{t("overview.guideEyebrow")}</small>
          <strong>{t("overview.guideTitle")}</strong>
          <span>{t("overview.guideDesc")}</span>
        </span>
        <span className="tutorial-card__action">
          {t("overview.guideAction")}
          <ArrowRight size={16} strokeWidth={1.9} />
        </span>
      </button>
    </div>
  );
}
