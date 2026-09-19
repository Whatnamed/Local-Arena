import { useState } from "react";
import {
  Activity,
  ArrowRight,
  BookOpenText,
  Crosshair,
  FileCheck2,
  Languages,
  type LucideIcon,
} from "lucide-react";
import StatusBar from "../components/StatusBar";
import LaunchCard from "./LaunchCard";
import { useToast } from "../components/Toast";
import { useStore } from "../state/store";
import { useT, type I18nKey } from "../i18n";

export type DashboardTarget =
  | "settings" | "installation" | "languages" | "weaponPresets" | "commands" | "guide";

type Tile = {
  /** Navigates to a top-level view. */
  view?: DashboardTarget;
  /** Runs `export_diagnostics` instead of navigating. */
  diagnostics?: boolean;
  key: I18nKey;
  icon: LucideIcon;
};

const TILES: Tile[] = [
  { view: "weaponPresets", key: "weapons.title", icon: Crosshair },
  { view: "installation", key: "set.installation", icon: FileCheck2 },
  { diagnostics: true, key: "overview.exportDiagnostics", icon: Activity },
  { view: "languages", key: "set.languages", icon: Languages },
  { view: "guide", key: "nav.guide", icon: BookOpenText },
];

export default function OverviewDashboard({ onNavigate }: { onNavigate: (view: DashboardTarget) => void }) {
  const t = useT();
  const { exportDiagnostics } = useStore();
  const toast = useToast();
  const [exporting, setExporting] = useState(false);

  // The diagnostics tile is an action, not a page: the archive is written by the
  // backend and the store already reports a failure through the error modal.
  const runDiagnostics = async () => {
    if (exporting) return;
    setExporting(true);
    const report = await exportDiagnostics();
    setExporting(false);
    if (report) toast.show(t("install.exported", { path: report.path }), "green");
  };

  return (
    <div className="dashboard">
      <header className="workspace__head">
        <span className="workspace__eyebrow">Local Arena</span>
        <h1>{t("nav.overview")}</h1>
      </header>
      <StatusBar onOpenSettings={() => onNavigate("settings")} />

      <div className="dashboard__controls">
        <LaunchCard />
      </div>

      <div className="quick-grid" role="navigation" aria-label={t("overview.quickActions")}>
        {TILES.map(({ view, diagnostics, key, icon: Icon }) => (
          <button
            key={key}
            className="quick-tile"
            onClick={() => {
              if (diagnostics) void runDiagnostics();
              else if (view) onNavigate(view);
            }}
          >
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
