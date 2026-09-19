import { useState } from "react";
import StatusDot, { type Status } from "./StatusDot";
import Modal from "./Modal";
import { useStore } from "../state/store";
import { useT } from "../i18n";
import { isolationPhase, ISOLATION_PRESENTATION } from "../lib/launchGate";
import "./StatusBar.css";

export default function StatusBar({ onOpenSettings }: { onOpenSettings?: () => void }) {
  const { directory, files, ready, installation, isolation, csgoPath, process: cs2Process } = useStore();
  const t = useT();
  const [showMissing, setShowMissing] = useState(false);

  const dirStatus: Status = !ready
    ? "unknown"
    : directory?.valid
    ? "green"
    : "red";

  const filesStatus: Status = !ready
    ? "unknown"
    : !directory?.valid
    ? "off" // can't validate without a directory
    : files?.ok
    ? "green"
    : "red";

  const damaged = (installation?.missing.length ?? 0) + (installation?.corrupt.length ?? 0);
  const installStatus: Status = !ready
    ? "unknown"
    : !directory?.valid
    ? "off"
    : !installation?.installed
    ? "yellow"
    : damaged
    ? "yellow"
    : "green";

  // The launch row repeats the Overview card in one line, with the same wording:
  // what is observable on disk right now, never a "mode".
  const phase = isolationPhase(csgoPath, isolation, !!cs2Process?.running);
  const isolationStatus: Status = ISOLATION_PRESENTATION[phase].status;
  const isolationHint = t(ISOLATION_PRESENTATION[phase].title);

  const dirHint = !directory?.steam_found
    ? t("st.steamNotFound")
    : directory?.valid
    ? directory.selected ?? ""
    : directory?.needs_choice
    ? t("st.multiple")
    : t("st.notLocated");

  return (
    <>
      <section className="statusbar glass">
        <div className="statusbar__item">
          <div className="statusbar__text">
            <span className="statusbar__label">{t("st.directory")}</span>
            <span className="statusbar__hint" title={dirHint}>
              {dirHint}
            </span>
          </div>
          <StatusDot status={dirStatus} size={12} pulse={!ready} />
        </div>

        <div className="statusbar__divider" />

        <div className="statusbar__item">
          <div className="statusbar__text">
            <span className="statusbar__label">{t("st.files")}</span>
            <span className="statusbar__hint">
              {filesStatus === "green"
                ? t("st.allPresent")
                : filesStatus === "red"
                ? files?.misplaced
                  ? t("st.wrongLocation")
                  : t("st.missing", { n: files?.missing.length ?? 0 })
                : filesStatus === "off"
                ? "—"
                : t("st.checking")}
            </span>
          </div>
          <StatusDot
            status={filesStatus}
            size={12}
            pulse={!ready}
            onClick={
              filesStatus === "red" ? () => setShowMissing(true) : undefined
            }
            title={filesStatus === "red" ? t("st.viewMissing") : undefined}
          />
        </div>

        <div className="statusbar__divider" />

        <div className={`statusbar__item ${onOpenSettings ? "is-clickable" : ""}`} onClick={onOpenSettings} title={onOpenSettings ? t("set.installation") : undefined}>
          <div className="statusbar__text">
            <span className="statusbar__label">{t("st.installation")}</span>
            <span className="statusbar__hint">
              {!ready
                ? t("st.checking")
                : installation?.installed
                ? `v${installation.package_version}`
                : t("st.notInstalled")}
            </span>
          </div>
          <StatusDot status={installStatus} size={12} pulse={!ready} />
        </div>

        <div className="statusbar__divider" />

        <div className="statusbar__item">
          <div className="statusbar__text">
            <span className="statusbar__label">{t("launch.state")}</span>
            <span className="statusbar__hint" title={isolationHint}>
              {isolationHint}
            </span>
          </div>
          <StatusDot status={isolationStatus} size={12} pulse={!ready} />
        </div>
      </section>

      <Modal
        open={showMissing}
        title={`${t("err.missingFiles")} (${files?.missing.length ?? 0})`}
        onClose={() => setShowMissing(false)}
        width={420}
        footer={
          <button className="btn-primary" onClick={() => setShowMissing(false)}>
            {t("common.ok")}
          </button>
        }
      >
        {files?.misplaced && (
          <p className="missing-note selectable">
            {t("st.wrongLocation")}
            <br />
            <code>{files.misplaced}</code>
          </p>
        )}
        <ul className="missing-list selectable">
          {files?.missing.map((m) => (
            <li key={m}>{m}</li>
          ))}
        </ul>
      </Modal>
    </>
  );
}
