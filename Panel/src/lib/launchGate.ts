import type { IsolationStatus } from "./api";
import type { Status } from "../components/StatusDot";
import type { I18nKey } from "../i18n";

/**
 * The observable launch situations, derived only from what the backend reports:
 * whether `gameinfo.gi` is readable, whether it still carries one of this
 * project's search paths, whether a launch transaction journal is open, and
 * whether CS2 is running for the selected directory.
 *
 * There is deliberately no "mode" here. The durable state is `clean`; every
 * other phase is a transient launch window or a transaction that still has to
 * converge back to clean.
 */
export type IsolationPhase =
  | "no_directory"
  | "unknown"
  | "gameinfo_missing"
  | "clean"
  | "preparing"
  | "armed_running"
  | "unfinished_transaction"
  | "paths_present";

export function isolationPhase(
  selected: string | null,
  isolation: IsolationStatus | null,
  cs2Running: boolean
): IsolationPhase {
  if (!selected) return "no_directory";
  if (!isolation) return "unknown";
  if (!isolation.gameinfo_present) return "gameinfo_missing";
  if (isolation.clean) return "clean";
  if (isolation.pending === "prepared") return "preparing";
  if (isolation.pending === "inserted") return cs2Running ? "armed_running" : "unfinished_transaction";
  return "paths_present";
}

export type IsolationPresentation = {
  tone: "green" | "yellow" | "red" | "neutral";
  status: Status;
  title: I18nKey;
  desc: I18nKey;
};

export const ISOLATION_PRESENTATION: Record<IsolationPhase, IsolationPresentation> = {
  no_directory: { tone: "neutral", status: "off", title: "launch.needDirectory", desc: "set.directoryDesc" },
  unknown: { tone: "neutral", status: "unknown", title: "launch.reading", desc: "set.directoryDesc" },
  gameinfo_missing: { tone: "red", status: "red", title: "launch.gameinfoMissing", desc: "launch.gameinfoMissingDesc" },
  clean: { tone: "green", status: "green", title: "launch.clean", desc: "launch.cleanDesc" },
  preparing: { tone: "yellow", status: "yellow", title: "launch.preparing", desc: "launch.preparingDesc" },
  armed_running: { tone: "yellow", status: "yellow", title: "launch.inserted", desc: "launch.insertedDesc" },
  unfinished_transaction: { tone: "yellow", status: "yellow", title: "launch.recover", desc: "launch.recoverDesc" },
  paths_present: { tone: "red", status: "red", title: "launch.pathsPresent", desc: "launch.pathsPresentDesc" },
};

/**
 * Only a directory with a readable gameinfo.gi and no CS2 holding it can start a
 * launch window. Whether the file is currently clean is intentionally not a
 * precondition: `launch_local_cosmetics` heals an interrupted transaction first,
 * and the Panel must not guess a state the backend has not observed.
 */
export function canLaunchLocalCosmetics(
  selected: string | null,
  isolation: IsolationStatus | null,
  cs2Running: boolean,
  working: boolean
): boolean {
  return !!selected && !!isolation?.gameinfo_present && !cs2Running && !working;
}
