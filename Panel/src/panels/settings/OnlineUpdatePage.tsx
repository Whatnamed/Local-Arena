import { useCallback, useEffect, useState } from "react";
import { ArrowRight, ExternalLink, RefreshCw } from "lucide-react";
import { api, toAppError, type OnlineUpdateSnapshot } from "../../lib/api";
import { useT } from "../../i18n";
import { openExternalUrl } from "../../lib/platform";

function formatBytes(value: number) {
  if (!value) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1);
  return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`;
}

function formatTime(value: number | null) {
  return value ? new Date(value * 1000).toLocaleString() : "--";
}

export default function OnlineUpdatePage() {
  const t = useT();
  const [snapshot, setSnapshot] = useState<OnlineUpdateSnapshot | null>(null);
  const [localError, setLocalError] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);

  const refreshSnapshot = useCallback(async () => {
    try {
      setSnapshot(await api.getUpdateSnapshot());
    } catch {
      /* The read-only status surface may remain empty until an explicit check. */
    }
  }, []);

  useEffect(() => {
    void refreshSnapshot();
  }, [refreshSnapshot]);

  const check = async () => {
    setChecking(true);
    setLocalError(null);
    try {
      setSnapshot(await api.checkOnlineUpdates(true));
    } catch (error) {
      setLocalError(toAppError(error).detail);
      await refreshSnapshot();
    } finally {
      setChecking(false);
    }
  };

  const componentSection = (component: "panel" | "plugin") => {
    const state = snapshot?.[component];
    const available = !!state?.reference_available;
    return (
      <section className="upd-card" key={component}>
        <div className="upd-card__head">
          <div>
            <strong>{component === "panel" ? t("update.panel") : t("update.plugin")}</strong>
            <small>{t("update.referenceDesc")}</small>
          </div>
          <span className={`update-status update-status--${available ? "available" : "current"}`}>
            {available ? t("update.reference") : t("update.current")}
          </span>
        </div>
        <div className="upd-card__versions">
          <span className="upd-ver">
            <small>{t("update.currentVersion")}</small>
            <strong>{state?.current_version ?? "--"}</strong>
          </span>
          <ArrowRight size={18} className={`upd-arrow ${available ? "is-hot" : ""}`} aria-hidden="true" />
          <span className="upd-ver">
            <small>{t("update.latestVersion")}</small>
            <strong className={available ? "is-new" : ""}>{state?.latest_version ?? "--"}</strong>
          </span>
          <span className="upd-ver upd-ver--size">
            <small>{t("update.size")}</small>
            <strong>{formatBytes(state?.total_bytes ?? 0)}</strong>
          </span>
        </div>
      </section>
    );
  };

  return (
    <div className="online-update-page">
      <div className="update-toolbar">
        <span><small>{t("update.lastChecked")}</small><strong>{formatTime(snapshot?.checked_at ?? null)}</strong></span>
        <div>
          {snapshot?.release_notes_url && (
            <button title={t("update.releaseNotes")} onClick={() => openExternalUrl(snapshot.release_notes_url!)}>
              <ExternalLink size={16} />{t("update.releaseNotes")}
            </button>
          )}
          <button disabled={checking} onClick={check}>
            <RefreshCw size={16} />{checking ? t("update.checking") : t("update.check")}
          </button>
        </div>
      </div>
      {(localError || snapshot?.error) && <div className="update-error">{localError ?? snapshot?.error}</div>}
      <section className="update-primary-action">
        <span>
          <strong>{t("update.readOnlyTitle")}</strong>
          <small>{t("update.readOnlyDesc")}</small>
        </span>
      </section>
      <p className="upd-note update-primary-note">{t("update.readOnlyNote")}</p>
      <div className="upd-grid">
        {componentSection("panel")}
        {componentSection("plugin")}
      </div>
    </div>
  );
}
