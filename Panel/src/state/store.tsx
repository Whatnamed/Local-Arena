import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  api,
  toAppError,
  type AppConfig,
  type AppError,
  type Cs2ProcessInfo,
  type DirectoryInfo,
  type DiagnosticReport,
  type DropKnivesState,
  type FilesReport,
  type InstallationInspection,
  type InstallPlan,
  type InstallTransactionResult,
  type IsolationStatus,
  type RestoreResult,
} from "../lib/api";

export type Store = {
  ready: boolean;
  config: AppConfig | null;
  directory: DirectoryInfo | null;
  process: Cs2ProcessInfo | null;
  installation: InstallationInspection | null;
  files: FilesReport | null;
  /** Observable launch-isolation state of `gameinfo.gi`. There is no "mode":
   *  the durable state is always clean, and a project search path only exists
   *  inside an explicit local-cosmetics launch window. */
  isolation: IsolationStatus | null;
  /** Drop-knife "changed while CS2 running, pending restart" flag. Persisted,
   *  so the yellow light survives a full close/reopen of the panel. */
  dropKnivesPending: boolean;
  dropKnives: DropKnivesState | null;
  csgoPath: string | null;
  /** Last global error (for the error modal). */
  error: AppError | null;
  clearError: () => void;
  reportError: (e: unknown) => void;
  refreshDirectory: () => Promise<DirectoryInfo | null>;
  refreshFiles: () => Promise<void>;
  refreshIsolation: () => Promise<IsolationStatus | null>;
  refreshProcess: (silent?: boolean) => Promise<Cs2ProcessInfo | null>;
  refreshAll: (silent?: boolean) => Promise<void>;
  updateConfig: (patch: Partial<AppConfig>) => Promise<boolean>;
  chooseDirectory: (path: string) => Promise<void>;
  getInstallPlan: () => Promise<InstallPlan | null>;
  verifyInstallation: () => Promise<InstallationInspection | null>;
  installPayload: () => Promise<InstallTransactionResult | null>;
  repairPayload: () => Promise<InstallTransactionResult | null>;
  restorePayload: () => Promise<RestoreResult | null>;
  restorePristineCs2: () => Promise<RestoreResult | null>;
  exportDiagnostics: () => Promise<DiagnosticReport | null>;
  launchLocalCosmetics: () => Promise<boolean>;
  applyDropKnives: (
    bindKey: string,
    selected: number[]
  ) => Promise<DropKnivesState | null>;
};

/** A boolean flag persisted in localStorage so it survives a full close/reopen
 *  of the panel (used for the per-section "changed while CS2 running" lights). */
function usePersistedFlag(key: string): [boolean, (v: boolean) => void] {
  const [value, setValue] = useState<boolean>(() => localStorage.getItem(key) === "1");
  const set = useCallback(
    (v: boolean) => {
      setValue(v);
      try {
        localStorage.setItem(key, v ? "1" : "0");
      } catch {
        /* localStorage unavailable — fall back to in-memory only */
      }
    },
    [key]
  );
  return [value, set];
}

const Ctx = createContext<Store | null>(null);

export function useStore(): Store {
  const s = useContext(Ctx);
  if (!s) throw new Error("useStore must be used within AppStateProvider");
  return s;
}

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [config, setConfig] = useState<AppConfig | null>(null);
  const [directory, setDirectory] = useState<DirectoryInfo | null>(null);
  const [process, setProcess] = useState<Cs2ProcessInfo | null>(null);
  const [installation, setInstallation] = useState<InstallationInspection | null>(null);
  const [files, setFiles] = useState<FilesReport | null>(null);
  const [isolation, setIsolation] = useState<IsolationStatus | null>(null);
  const [dropKnivesPending, setDropKnivesPending] =
    usePersistedFlag("cs2bi.dropKnivesPending");
  const [dropKnives, setDropKnives] = useState<DropKnivesState | null>(null);
  const [error, setError] = useState<AppError | null>(null);
  const configRef = useRef<AppConfig | null>(null);
  const lastSnapshotErrorLogRef = useRef(0);
  configRef.current = config;

  const reportError = useCallback((e: unknown) => {
    const normalized = toAppError(e);
    setError(normalized);
    void api.recordPanelError(normalized, window.location.pathname).catch(() => {});
  }, []);
  const clearError = useCallback(() => setError(null), []);

  const refreshFiles = useCallback(async () => {
    const csgo = directory?.valid ? directory.selected : null;
    if (!csgo) {
      setFiles(null);
      return;
    }
    try {
      setFiles(await api.validateFiles(csgo));
    } catch (e) {
      setFiles(null);
      reportError(e);
    }
  }, [directory, reportError]);

  const refreshIsolation = useCallback(async () => {
    const csgo = directory?.valid ? directory.selected : null;
    if (!csgo) {
      setIsolation(null);
      return null;
    }
    try {
      const status = await api.getLaunchIsolation(csgo);
      setIsolation(status);
      return status;
    } catch (e) {
      setIsolation(null);
      reportError(e);
      return null;
    }
  }, [directory, reportError]);

  const applyDropKnives = useCallback(
    async (bindKey: string, selected: number[]) => {
      const csgo = directory?.valid ? directory.selected : null;
      if (!csgo) return null;
      try {
        const info = await api.setDropKnives(csgo, bindKey, selected);
        setDropKnives(info);
        setDropKnivesPending(info.cs2_running);
        return info;
      } catch (e) {
        reportError(e);
        return null;
      }
    },
    [directory, reportError]
  );

  const refreshDirectory = useCallback(async () => {
    try {
      const info = await api.detectDirectories();
      setDirectory(info);
      return info;
    } catch (e) {
      reportError(e);
      return null;
    }
  }, [reportError]);

  const refreshProcess = useCallback(async (silent = false) => {
    const csgo = directory?.valid ? directory.selected : null;
    try {
      const info = await api.getCs2Process(csgo);
      setProcess(info);
      return info;
    } catch (e) {
      if (!silent) reportError(e);
      return null;
    }
  }, [directory, reportError]);

  const refreshAll = useCallback(async (silent = false) => {
    try {
      const snapshot = await api.getRuntimeSnapshot();
      setDirectory(snapshot.directory);
      setProcess(snapshot.process);
      setInstallation(snapshot.installation);
      setFiles(snapshot.files);
      setIsolation(snapshot.isolation);
      setDropKnives(snapshot.drop_knives);

      if (!snapshot.process.running) {
        setDropKnivesPending(false);
      }
    } catch (e) {
      // Keep the complete last-good snapshot, but refresh the process lock
      // independently so a transient disk scan cannot leave install disabled.
      if (silent) {
        await refreshProcess(true);
        const now = Date.now();
        if (now - lastSnapshotErrorLogRef.current >= 30_000) {
          lastSnapshotErrorLogRef.current = now;
          void api.recordPanelError(toAppError(e), "runtime-snapshot-background").catch(() => {});
        }
        return;
      }
      setDirectory(null);
      setProcess(null);
      setInstallation(null);
      setFiles(null);
      setIsolation(null);
      setDropKnives(null);
      setDropKnivesPending(false);
      reportError(e);
    }
  }, [refreshProcess, reportError, setDropKnivesPending]);

  const updateConfig = useCallback(
    async (patch: Partial<AppConfig>) => {
      const base = configRef.current;
      if (!base) return false;
      const next = { ...base, ...patch };
      setConfig(next);
      try {
        await api.saveConfig(next);
        return true;
      } catch (e) {
        setConfig(base);
        reportError(e);
        return false;
      }
    },
    [reportError]
  );

  const chooseDirectory = useCallback(
    async (path: string) => {
      try {
        await api.selectDirectory(path);
        await refreshAll();
      } catch (e) {
        reportError(e);
      }
    },
    [refreshAll, reportError]
  );

  const getInstallPlan = useCallback(async () => {
    const csgo = directory?.valid ? directory.selected : null;
    if (!csgo) return null;
    try { return await api.getInstallPlan(csgo); }
    catch (e) { reportError(e); return null; }
  }, [directory, reportError]);

  const verifyInstallation = useCallback(async () => {
    const csgo = directory?.valid ? directory.selected : null;
    if (!csgo) return null;
    try {
      const [inspection, report] = await Promise.all([
        api.inspectInstallation(csgo),
        api.validateFiles(csgo),
      ]);
      setInstallation(inspection);
      setFiles(report);
      return inspection;
    } catch (e) {
      reportError(e);
      return null;
    }
  }, [directory, reportError]);

  const runInstallAction = useCallback(async (action: "install" | "repair") => {
    const csgo = directory?.valid ? directory.selected : null;
    if (!csgo) return null;
    try {
      const result = action === "install" ? await api.installPayload(csgo) : await api.repairPayload(csgo);
      await refreshAll();
      return result;
    } catch (e) { reportError(e); return null; }
  }, [directory, refreshAll, reportError]);

  const installPayload = useCallback(() => runInstallAction("install"), [runInstallAction]);
  const repairPayload = useCallback(() => runInstallAction("repair"), [runInstallAction]);

  const restorePayload = useCallback(async () => {
    const csgo = directory?.valid ? directory.selected : null;
    if (!csgo) return null;
    try {
      const result = await api.restorePayload(csgo);
      await refreshAll();
      return result;
    } catch (e) { reportError(e); return null; }
  }, [directory, refreshAll, reportError]);

  const restorePristineCs2 = useCallback(async () => {
    const csgo = directory?.valid ? directory.selected : null;
    if (!csgo) return null;
    try {
      const result = await api.restorePristineCs2(csgo);
      await refreshAll();
      return result;
    } catch (e) { reportError(e); return null; }
  }, [directory, refreshAll, reportError]);

  const exportDiagnostics = useCallback(async () => {
    const csgo = directory?.valid ? directory.selected : null;
    try { return await api.exportDiagnostics(csgo); }
    catch (e) { reportError(e); return null; }
  }, [directory, reportError]);

  // The only launch path this product has: the Panel arms the temporary search
  // path, starts CS2 with -insecure, and the clean state is restored afterwards.
  // Success here is "CS2 was started", so the visible state is read back from
  // disk instead of inferred from the call.
  const launchLocalCosmetics = useCallback(async () => {
    try {
      await api.launchLocalCosmetics();
      await refreshAll();
      return true;
    } catch (e) {
      reportError(e);
      await refreshAll().catch(() => {});
      return false;
    }
  }, [refreshAll, reportError]);

  // Global safety net: surface any unexpected error/rejection as a modal so the
  // UI never fails silently.
  useEffect(() => {
    const onErr = (e: ErrorEvent) => {
      if (e.error) reportError(e.error);
    };
    const onRej = (e: PromiseRejectionEvent) => reportError(e.reason);
    window.addEventListener("error", onErr);
    window.addEventListener("unhandledrejection", onRej);
    return () => {
      window.removeEventListener("error", onErr);
      window.removeEventListener("unhandledrejection", onRej);
    };
  }, [reportError]);

  // Boot: load config, then take one consolidated runtime snapshot. The Panel
  // never writes launch options or gameinfo.gi at startup; recovery of an
  // interrupted launch transaction belongs to the Rust side.
  useEffect(() => {
    (async () => {
      try {
        const cfg = await api.getConfig();
        setConfig(cfg);
      } catch (e) {
        reportError(e);
      }
      await refreshDirectory();
      await refreshAll();
      setReady(true);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Live updates: one consolidated backend snapshot every two seconds keeps all
  // indicator lights and buttons reflect the current on-disk / CS2-running state
  // without the user reopening the panel. Silent (never pops an error modal),
  // non-overlapping (skips a tick if the previous scan is still in flight), and
  // paused while the window is hidden/minimized to avoid needless work.
  const pollingRef = useRef(false);
  useEffect(() => {
    if (!ready) return;
    const tick = async () => {
      if (document.visibilityState !== "visible") return;
      if (pollingRef.current) return;
      pollingRef.current = true;
      try {
        await refreshAll(true);
      } finally {
        pollingRef.current = false;
      }
    };
    const id = window.setInterval(tick, 2000);
    const onFocus = () => { void tick(); };
    const onVisibility = () => {
      if (document.visibilityState === "visible") void tick();
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [ready, refreshAll]);

  // Keep every panel-owned local preference mirrored beside the executable.
  // The backend write only runs when the serialized state actually changes.
  useEffect(() => {
    if (!ready) return;
    let last = "";
    const sync = () => {
      const entries: Record<string, string> = {};
      for (let index = 0; index < localStorage.length; index += 1) {
        const key = localStorage.key(index);
        if (!key?.startsWith("cs2bi.")) continue;
        const value = localStorage.getItem(key);
        if (value !== null) entries[key] = value;
      }
      const serialized = JSON.stringify(entries);
      if (serialized === last) return;
      last = serialized;
      void api.savePanelMemory(entries).catch((error) => {
        void api.recordPanelError(toAppError(error), "panel-memory-sync").catch(() => {});
      });
    };
    sync();
    const id = window.setInterval(sync, 1000);
    return () => window.clearInterval(id);
  }, [ready]);

  const value: Store = {
    ready,
    config,
    directory,
    process,
    installation,
    files,
    isolation,
    dropKnivesPending,
    dropKnives,
    csgoPath: directory?.valid ? directory.selected : null,
    error,
    clearError,
    reportError,
    refreshDirectory,
    refreshFiles,
    refreshIsolation,
    refreshProcess,
    refreshAll,
    updateConfig,
    chooseDirectory,
    getInstallPlan,
    verifyInstallation,
    installPayload,
    repairPayload,
    restorePayload,
    restorePristineCs2,
    exportDiagnostics,
    launchLocalCosmetics,
    applyDropKnives,
  };

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

type PreviewStore = Pick<Store, "config" | "csgoPath" | "process" | "reportError">;

// Scoped provider for browser-only component previews. It intentionally exposes
// only the state consumed by the previewed surface and never invokes Tauri.
export function AppStatePreviewProvider({ children, value }: { children: ReactNode; value: PreviewStore }) {
  return <Ctx.Provider value={value as Store}>{children}</Ctx.Provider>;
}
