import { invoke as tauriInvoke } from "@tauri-apps/api/core";

function invoke<T>(command: string, args?: Record<string, unknown>) {
  return tauriInvoke<T>(command, args);
}

/** Mirrors Rust `AppError` (error.rs). Codes are stable & not localized. */
export type AppError = {
  code: string;
  category: string;
  detail: string;
};

export function isAppError(e: unknown): e is AppError {
  return (
    typeof e === "object" &&
    e !== null &&
    "code" in e &&
    "category" in e &&
    typeof (e as AppError).code === "string"
  );
}

/** Normalize any thrown value into an AppError so the UI always has a code. */
export function toAppError(e: unknown): AppError {
  if (isAppError(e)) return e;

  if (typeof e === "string") {
    try {
      const parsed: unknown = JSON.parse(e);
      if (isAppError(parsed)) return parsed;
    } catch {
      // Plain strings are valid Tauri rejection details.
    }
    return { code: "E1099", category: "internal", detail: e || "Unknown error" };
  }

  if (e instanceof Error) {
    return {
      code: "E1099",
      category: "internal",
      detail: `${e.name}: ${e.message}`,
    };
  }

  if (typeof e === "object" && e !== null && "message" in e) {
    const message = (e as { message?: unknown }).message;
    if (typeof message === "string") {
      return { code: "E1099", category: "internal", detail: message };
    }
  }

  let detail = "Unknown error";
  try {
    detail = JSON.stringify(e) || String(e);
  } catch {
    detail = String(e);
  }
  return {
    code: "E1099",
    category: "internal",
    detail,
  };
}

// ---- DTOs (mirror src-tauri) ----
export type DirectoryInfo = {
  candidates: string[];
  selected: string | null;
  valid: boolean;
  needs_choice: boolean;
  steam_found: boolean;
};

export type FilesReport = {
  ok: boolean;
  total: number;
  present: number;
  missing: string[];
  /** Wrong folder the plugin was extracted into, if detected. */
  misplaced: string | null;
};

export type Cs2ProcessInfo = {
  running: boolean;
  pid: number | null;
  executable: string | null;
  path_accessible: boolean;
  matches_selected: boolean;
};

export type InstallationSource =
  | "clean"
  | "managed_plus"
  | "legacy_plus"
  | "upstream"
  | "mixed_unknown";

export type MigrationKind =
  | "fresh_install"
  | "managed_upgrade"
  | "adopt_legacy_plus"
  | "replace_upstream"
  | "blocked";

export type RestoreBaseline =
  | "steam_original"
  | "pre_migration"
  | "existing_record"
  | "none";

export type InstallationInspection = {
  installed: boolean;
  package_version: string | null;
  manifest_available: boolean;
  total: number;
  healthy: number;
  missing: string[];
  corrupt: string[];
  restore_available: boolean;
  backup_path: string | null;
  interrupted_transaction: boolean;
  source: InstallationSource;
  source_version: string | null;
  source_evidence: string[];
  migration_kind: MigrationKind;
  restore_baseline: RestoreBaseline;
  can_install: boolean;
};

export type InstallPlan = {
  package_version: string;
  target: string;
  total_files: number;
  new_files: number;
  overwritten_files: number;
  backup_path: string;
  required_target_bytes: number;
  available_target_bytes: number;
  required_backup_bytes: number;
  available_backup_bytes: number;
  writable: boolean;
  source: InstallationSource;
  source_version: string | null;
  source_evidence: string[];
  migration_kind: MigrationKind;
  restore_baseline: RestoreBaseline;
  can_install: boolean;
};

export type InstallTransactionResult = {
  package_version: string;
  installed_files: number;
  backup_path: string;
  repaired: boolean;
  welcome_story_eligible: boolean;
};

export type RestoreResult = {
  restored_files: number;
  removed_files: number;
  preserved_files: number;
  presets_backup: string | null;
  steam_verify_uri: string;
  result_kind: "restore_previous" | "pristine";
};

export type DiagnosticReport = {
  path: string;
  files_collected: number;
};

export type UiMemory = {
  schema_version: number;
  saved_at: number;
  entries: Record<string, string>;
};

export type DropKnivesState = {
  bind_key: string;
  selected: number[];
  cfg_present: boolean;
  cs2_running: boolean;
};

export type KnifePreset = {
  paint: number;
  seed: number;
  wear: number;
  name_tag: string;
  stattrak_enabled: boolean;
  stattrak_count: number;
  souvenir_enabled?: boolean;
  stickers?: StickerPreset[];
  charm?: CharmPreset | null;
};

export type StickerPreset = {
  slot: number;
  id: number;
  schema: number;
  wear: number;
  scale: number;
  rotation: number;
  offset_x: number;
  offset_y: number;
  custom_position: boolean;
};

export type CharmPreset = {
  id: number;
  placement_id: number;
  seed: number;
};

export type GlovePreset = {
  enabled: boolean;
  defindex: number;
  paint: number;
  seed: number;
  wear: number;
};

export type CosmeticsTeam = "ct" | "t";

export type TeamCosmeticLoadout = {
  agent_model: string;
  default_knife_defindex: number;
  knife_presets: Record<string, KnifePreset>;
  glove: GlovePreset;
  gun_presets: Record<string, KnifePreset>;
};

export type KnifeCustomizerConfig = {
  schema_version: 5;
  enabled: boolean;
  apply_to_human_players: boolean;
  music_kit_id: number;
  loadouts: Record<CosmeticsTeam, TeamCosmeticLoadout>;
  shared_weapon_links: Record<string, boolean>;
  stickers_enabled: boolean;
  charms_enabled: boolean;
  agents_enabled: boolean;
};

export type KnifeCustomizerState = {
  plugin_present: boolean;
  config_present: boolean;
  cs2_running: boolean;
  config: KnifeCustomizerConfig;
};

export type CosmeticsPresetExportResult = { path: string; size_bytes: number };
export type CosmeticsPresetImportResult = { state: KnifeCustomizerState; backup_path: string | null };

/**
 * Mirrors Rust `launch_isolation::IsolationStatus`.
 *
 * The durable state of `gameinfo.gi` is always the clean one; the project
 * search path only exists inside an explicit local-cosmetics launch window.
 * `pending` is the phase of an open transaction journal, never a "mode".
 */
export type IsolationStatus = {
  gameinfo_present: boolean;
  clean: boolean;
  project_paths_present: string[];
  pending: "prepared" | "inserted" | null;
  ticket_live: boolean;
};

export type LaunchResult = {
  options: string;
  insecure: boolean;
};

export type AppConfig = {
  language: string | null;
  drop_knife_bind: string;
  drop_knife_subclasses: number[];
  csgo_path: string | null;
  first_run_done: boolean;
  first_run_step?: string | null;
  welcome_story_prompt_presented: boolean;
  experimental_features_enabled?: boolean;
  experimental_stickers_enabled?: boolean;
};

export type AppearanceStyle = "paper" | "clean" | "compact" | "immersive";
export type AppearancePalette = "terracotta" | "sky" | "monochrome" | "grass" | "mist" | "berry" | "custom";
export type AppearanceFont = "humanist" | "modern" | "clear" | "classic" | "technical" | "custom";
export type AppearanceDensity = "compact" | "standard" | "relaxed";
export type AppearanceLevel = "none" | "subtle" | "soft" | "strong";
export type AppearanceMotion = "off" | "reduced" | "full";

export type AppearanceBackground = {
  data_url: string;
  fit: "cover" | "contain";
  position_x: number;
  position_y: number;
  dim: number;
  blur: number;
};

export type AppearanceLogo = {
  data_url: string;
  fit: "cover" | "contain";
  shape: "rounded" | "square" | "circle";
};

export type AppearanceCustomFont = {
  data_url: string;
  file_name: string;
  format: "ttf" | "otf" | "woff" | "woff2";
};

export type AppearanceConfig = {
  schema_version: 1;
  team_theme: string | null;
  brand_name: string;
  style: AppearanceStyle;
  palette: AppearancePalette;
  accent_color: string;
  font: AppearanceFont;
  density: AppearanceDensity;
  radius: AppearanceLevel;
  shadow: AppearanceLevel;
  motion: AppearanceMotion;
  custom_font: AppearanceCustomFont | null;
  background: AppearanceBackground | null;
  logo: AppearanceLogo | null;
};

export type AppearanceExportResult = { path: string; size_bytes: number };

export type InstallCheckStatus = "pass" | "warn" | "fail";
export type InstallCheckItem = {
  code: string;
  status: InstallCheckStatus;
  blocking: boolean;
  title: string;
  evidence: string;
  cause: string;
  action: string;
};
export type InstallCheckReport = {
  schema_version: number;
  generated_at_unix: number;
  target: string;
  overall: InstallCheckStatus;
  pass_count: number;
  warn_count: number;
  fail_count: number;
  blocking_fail_count: number;
  can_proceed: boolean;
  checks: InstallCheckItem[];
};

export type RuntimeSnapshot = {
  directory: DirectoryInfo;
  process: Cs2ProcessInfo;
  files: FilesReport | null;
  drop_knives: DropKnivesState | null;
  isolation: IsolationStatus | null;
  installation: InstallationInspection | null;
};

// ---- Command wrappers ----
export const api = {
  getConfig: () => invoke<AppConfig>("get_config"),
  saveConfig: (config: AppConfig) => invoke<void>("save_config", { config }),
  shouldPresentWelcomeStory: () => invoke<boolean>("should_present_welcome_story"),
  getAppearance: () => invoke<AppearanceConfig>("get_appearance"),
  saveAppearance: (config: AppearanceConfig) => invoke<AppearanceConfig>("save_appearance", { config }),
  exportAppearance: (destination: string) =>
    invoke<AppearanceExportResult>("export_appearance", { destination }),
  importAppearance: (source: string) =>
    invoke<AppearanceConfig>("import_appearance", { source }),
  getPanelMemory: () => invoke<UiMemory>("get_panel_memory"),
  savePanelMemory: (entries: Record<string, string>) =>
    invoke<UiMemory>("save_panel_memory", { entries }),
  recordPanelError: (error: AppError, context: string) =>
    invoke<void>("record_panel_error", { error: { ...error, context } }),
  getRuntimeSnapshot: () => invoke<RuntimeSnapshot>("get_runtime_snapshot"),
  getCs2Process: (csgo: string | null) =>
    invoke<Cs2ProcessInfo>("get_cs2_process", { csgo }),
  detectDirectories: () => invoke<DirectoryInfo>("detect_directories"),
  selectDirectory: (path: string) =>
    invoke<DirectoryInfo>("select_directory", { path }),
  validateFiles: (csgo: string) => invoke<FilesReport>("validate_files", { csgo }),
  getLaunchIsolation: (csgo: string) =>
    invoke<IsolationStatus>("get_launch_isolation", { csgo }),
  launchLocalCosmetics: () => invoke<LaunchResult>("launch_local_cosmetics"),
  runInstallChecks: (csgo: string) =>
    invoke<InstallCheckReport>("run_install_checks", { csgo }),
  getDropKnives: (csgo: string) =>
    invoke<DropKnivesState>("get_drop_knives", { csgo }),
  setDropKnives: (csgo: string, bindKey: string, selected: number[]) =>
    invoke<DropKnivesState>("set_drop_knives", { csgo, bindKey, selected }),
  getKnifeCustomizer: (csgo: string) =>
    invoke<KnifeCustomizerState>("get_knife_customizer", { csgo }),
  saveKnifeCustomizer: (csgo: string, config: KnifeCustomizerConfig) =>
    invoke<KnifeCustomizerState>("save_knife_customizer", { csgo, config }),
  exportCosmeticsPreset: (csgo: string, destination: string) =>
    invoke<CosmeticsPresetExportResult>("export_cosmetics_preset", { csgo, destination }),
  importCosmeticsPreset: (csgo: string, source: string) =>
    invoke<CosmeticsPresetImportResult>("import_cosmetics_preset", { csgo, source }),
  inspectInstallation: (csgo: string) =>
    invoke<InstallationInspection>("inspect_installation", { csgo }),
  getInstallPlan: (csgo: string) => invoke<InstallPlan>("get_install_plan", { csgo }),
  installPayload: (csgo: string) =>
    invoke<InstallTransactionResult>("install_payload", { csgo }),
  repairPayload: (csgo: string) =>
    invoke<InstallTransactionResult>("repair_payload", { csgo }),
  restorePayload: (csgo: string) => invoke<RestoreResult>("restore_payload", { csgo }),
  restorePristineCs2: (csgo: string) => invoke<RestoreResult>("restore_pristine_cs2", { csgo }),
  exportDiagnostics: (csgo: string | null) =>
    invoke<DiagnosticReport>("export_diagnostics", { csgo }),
};
