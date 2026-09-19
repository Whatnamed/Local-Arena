import { useState } from "react";
import { AlertTriangle, Info, Play, RefreshCw, ShieldCheck } from "lucide-react";
import Card from "../components/Card";
import StatusDot from "../components/StatusDot";
import { useToast } from "../components/Toast";
import { useStore } from "../state/store";
import { useT } from "../i18n";
import { canLaunchLocalCosmetics, isolationPhase, ISOLATION_PRESENTATION } from "../lib/launchGate";
import "./LaunchCard.css";

/**
 * The single entry point of this product: it shows what the Panel can observe
 * about `gameinfo.gi` right now, and one button that opens a local cosmetics
 * launch window. There is no mode to select and nothing to "switch back" to.
 */
export default function LaunchCard() {
  const {
    csgoPath, isolation, process, installation, ready,
    launchLocalCosmetics, refreshIsolation, refreshAll,
  } = useStore();
  const t = useT();
  const toast = useToast();
  const [busy, setBusy] = useState(false);

  const running = !!process?.running;
  const presentation = ISOLATION_PRESENTATION[isolationPhase(csgoPath, isolation, running)];
  const paths = isolation?.project_paths_present ?? [];
  const canLaunch = ready && canLaunchLocalCosmetics(csgoPath, isolation, running, busy);
  const blocked = !csgoPath
    ? t("launch.needDirectory")
    : running
      ? t("launch.gameRunning")
      : !isolation?.gameinfo_present
        ? t("launch.gameinfoMissingDesc")
        : "";
  // A missing runtime is not a launch blocker for the backend, but the game
  // would come back with no cosmetics, so it is worth saying out loud.
  const installHint = !!csgoPath && installation?.installed === false;

  const launch = async () => {
    if (!canLaunch) return;
    setBusy(true);
    const ok = await launchLocalCosmetics();
    setBusy(false);
    toast.show(t(ok ? "launch.started" : "launch.failed"), ok ? "green" : "red");
  };

  const recheck = async () => {
    if (busy) return;
    setBusy(true);
    if (csgoPath) await refreshIsolation();
    else await refreshAll();
    setBusy(false);
  };

  return (
    <Card title={t("launch.title")}>
      <div className="launch-card">
        <div className={`launch-card__state is-${presentation.tone}`}>
          <span className="launch-card__dot">
            <StatusDot status={presentation.status} size={10} pulse={!ready} />
          </span>
          <span className="launch-card__copy">
            <strong>{t(presentation.title)}</strong>
            <small>{t(presentation.desc)}</small>
            {paths.length > 0 && (
              <small className="launch-card__paths">
                {t("launch.searchPaths", { paths: paths.join(", ") })}
              </small>
            )}
          </span>
          <button
            className="launch-card__recheck"
            onClick={() => void recheck()}
            disabled={busy}
            title={t("launch.recheck")}
            aria-label={t("launch.recheck")}
          >
            <RefreshCw size={14} />
          </button>
        </div>

        <button className="launch-card__button" disabled={!canLaunch} onClick={() => void launch()}>
          {busy ? <Info size={16} /> : <Play size={16} />}
          <span>{busy ? t("launch.launching") : t("launch.button")}</span>
        </button>

        {blocked && <p className="launch-card__blocked">{blocked}</p>}
        {!blocked && installHint && (
          <p className="launch-card__blocked">
            <AlertTriangle size={14} aria-hidden="true" />
            <span>{t("launch.installFirst")}</span>
          </p>
        )}

        <ul className="launch-card__notes">
          <li>
            <ShieldCheck size={14} aria-hidden="true" />
            <span>{t("launch.steamHint")} {t("launch.insecureNote")}</span>
          </li>
          <li>
            <Info size={14} aria-hidden="true" />
            <span>{t("launch.restoreNote")}</span>
          </li>
        </ul>
      </div>
    </Card>
  );
}
