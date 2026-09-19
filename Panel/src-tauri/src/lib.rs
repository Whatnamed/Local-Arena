use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use std::sync::OnceLock;
use sysinfo::{ProcessesToUpdate, System};
use tauri::{AppHandle, Manager};

mod app_storage;
mod app_version;
mod appearance;
mod atomic_fs;
mod diagnostics;
mod install_checks;
mod installer;
mod launch_isolation;
mod logging;
mod runtime_state;
mod steam;
use installer::{InstallPlan, InstallTransactionResult, InstallationInspection, RestoreResult};
use install_checks::InstallCheckReport;
use launch_isolation::PreparedLaunch;
use runtime_state::{Cs2ProcessInfo, blocks_target_write, inspect_cs2_process};

type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug, Serialize)]
struct AppError {
    code: &'static str,
    category: &'static str,
    detail: String,
}

impl AppError {
    fn new(code: &'static str, category: &'static str, detail: impl Into<String>) -> Self {
        Self {
            code,
            category,
            detail: detail.into(),
        }
    }
    fn io(detail: impl Into<String>) -> Self {
        Self::new("E1001", "filesystem", detail)
    }
    fn invalid(detail: impl Into<String>) -> Self {
        Self::new("E1002", "validation", detail)
    }
    fn directory(detail: impl Into<String>) -> Self {
        Self::new("E1101", "directory", detail)
    }
    fn process(detail: impl Into<String>) -> Self {
        Self::new("E1201", "process", detail)
    }
    pub(crate) fn payload(detail: impl Into<String>) -> Self {
        Self::new("E1301", "payload", detail)
    }
    pub(crate) fn transaction(detail: impl Into<String>) -> Self {
        Self::new("E1401", "installation", detail)
    }
    fn preflight(detail: impl Into<String>) -> Self {
        Self::new("E1402", "installation", detail)
    }
    pub(crate) fn transaction_io(error: std::io::Error) -> Self {
        Self::transaction(error.to_string())
    }
    fn launch(detail: impl Into<String>) -> Self {
        Self::new("E1501", "launch", detail)
    }
}

impl From<std::io::Error> for AppError {
    fn from(value: std::io::Error) -> Self {
        Self::io(value.to_string())
    }
}

impl From<serde_json::Error> for AppError {
    fn from(value: serde_json::Error) -> Self {
        Self::invalid(value.to_string())
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct AppConfig {
    language: Option<String>,
    drop_knife_bind: String,
    drop_knife_subclasses: Vec<u16>,
    csgo_path: Option<String>,
    first_run_done: bool,
    #[serde(default)]
    first_run_step: Option<String>,
    #[serde(default)]
    welcome_story_prompt_presented: bool,
    #[serde(default)]
    experimental_features_enabled: bool,
    #[serde(default)]
    experimental_stickers_enabled: bool,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            language: Some("schinese".into()),
            drop_knife_bind: "\\".into(),
            drop_knife_subclasses: vec![],
            csgo_path: None,
            first_run_done: false,
            first_run_step: Some("language".into()),
            welcome_story_prompt_presented: false,
            experimental_features_enabled: false,
            experimental_stickers_enabled: false,
        }
    }
}

fn prepare_legacy_config_for_portable_state(mut config: AppConfig) -> AppConfig {
    config.first_run_done = false;
    config.first_run_step = Some("language".into());
    config.experimental_stickers_enabled = false;
    config
}

fn apply_release_feature_gates(_config: &mut AppConfig) {
}

const WELCOME_STORY_RELEASE_VERSION: &str = "1.4.3.3";

fn welcome_story_release_eligible(release_build: bool, display_version: &str) -> bool {
    release_build && display_version == WELCOME_STORY_RELEASE_VERSION
}

#[derive(Serialize)]
struct DirectoryInfo {
    candidates: Vec<String>,
    selected: Option<String>,
    valid: bool,
    needs_choice: bool,
    steam_found: bool,
}
#[derive(Serialize)]
struct FilesReport {
    ok: bool,
    total: usize,
    present: usize,
    missing: Vec<String>,
    misplaced: Option<String>,
}
#[derive(Clone, Debug, Serialize)]
struct LaunchResult {
    options: String,
    insecure: bool,
}

#[derive(Serialize)]
struct DropKnivesState {
    bind_key: String,
    selected: Vec<u16>,
    cfg_present: bool,
    cs2_running: bool,
}

#[derive(Serialize)]
struct RuntimeSnapshot {
    directory: DirectoryInfo,
    process: Cs2ProcessInfo,
    files: Option<FilesReport>,
    drop_knives: Option<DropKnivesState>,
    isolation: Option<launch_isolation::IsolationStatus>,
    installation: Option<InstallationInspection>,
}

#[derive(Deserialize)]
struct PanelErrorRecord {
    code: String,
    category: String,
    detail: String,
    context: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct StickerPreset {
    slot: u8,
    id: u32,
    #[serde(default)]
    schema: u32,
    wear: f32,
    scale: f32,
    rotation: f32,
    offset_x: f32,
    offset_y: f32,
    #[serde(default)]
    custom_position: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct CharmPreset {
    id: u32,
    placement_id: u32,
    seed: i32,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct KnifePreset {
    paint: i32,
    seed: i32,
    wear: f32,
    name_tag: String,
    stattrak_enabled: bool,
    stattrak_count: i32,
    #[serde(default)]
    souvenir_enabled: bool,
    #[serde(default)]
    stickers: Vec<StickerPreset>,
    #[serde(default)]
    charm: Option<CharmPreset>,
}

impl KnifePreset {
    fn base_value_eq(&self, other: &Self) -> bool {
        self.paint == other.paint
            && self.seed == other.seed
            && self.wear == other.wear
            && self.name_tag == other.name_tag
            && self.stattrak_enabled == other.stattrak_enabled
            && self.stattrak_count == other.stattrak_count
            && self.souvenir_enabled == other.souvenir_enabled
    }

    fn clone_without_decorations(&self) -> Self {
        Self {
            stickers: Vec::new(),
            charm: None,
            ..self.clone()
        }
    }
}

const DEFAULT_GLOVE_DEFINDEX: u16 = 5030;
const DEFAULT_GLOVE_PAINT: i32 = 10048;
const DEFAULT_GLOVE_WEAR: f32 = 0.01;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct GlovePreset {
    enabled: bool,
    defindex: u16,
    paint: i32,
    seed: i32,
    wear: f32,
}

impl Default for GlovePreset {
    fn default() -> Self {
        Self {
            enabled: false,
            defindex: DEFAULT_GLOVE_DEFINDEX,
            paint: DEFAULT_GLOVE_PAINT,
            seed: 0,
            wear: DEFAULT_GLOVE_WEAR,
        }
    }
}

const COSMETICS_SCHEMA_VERSION: u8 = 5;
const STICKER_RELEASE_ENABLED: bool = true;
const CT_ONLY_WEAPONS: &[u16] = &[3, 8, 10, 16, 27, 32, 34, 38, 60, 61];
const T_ONLY_WEAPONS: &[u16] = &[4, 7, 11, 13, 17, 29, 30, 39];
const SHARED_WEAPONS: &[u16] = &[
    1, 2, 9, 14, 19, 23, 24, 25, 26, 28, 31, 33, 35, 36, 40, 63, 64,
];

#[derive(Clone, Copy, Debug, PartialEq)]
enum WeaponSide {
    Ct,
    T,
    Shared,
}

fn weapon_side(defindex: u16) -> WeaponSide {
    if CT_ONLY_WEAPONS.contains(&defindex) {
        WeaponSide::Ct
    } else if T_ONLY_WEAPONS.contains(&defindex) {
        WeaponSide::T
    } else {
        WeaponSide::Shared
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct TeamLoadout {
    #[serde(default)]
    agent_model: String,
    #[serde(default)]
    default_knife_defindex: u16,
    #[serde(default)]
    knife_presets: BTreeMap<String, KnifePreset>,
    #[serde(default)]
    glove: GlovePreset,
    #[serde(default)]
    gun_presets: BTreeMap<String, KnifePreset>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct TeamLoadouts {
    #[serde(default)]
    ct: TeamLoadout,
    #[serde(default)]
    t: TeamLoadout,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct TeamGunConfig {
    #[serde(default)]
    schema_version: u8,
    #[serde(default)]
    ct: BTreeMap<String, KnifePreset>,
    #[serde(default)]
    t: BTreeMap<String, KnifePreset>,
    #[serde(default)]
    shared_weapon_links: BTreeMap<String, bool>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct KnifeCustomizerConfig {
    #[serde(default)]
    schema_version: u8,
    #[serde(default)]
    enabled: bool,
    #[serde(default = "default_true")]
    apply_to_human_players: bool,
    #[serde(default = "default_true")]
    apply_on_pickup: bool,
    #[serde(default)]
    music_kit_id: i32,
    #[serde(default)]
    loadouts: TeamLoadouts,
    #[serde(default)]
    shared_weapon_links: BTreeMap<String, bool>,
    #[serde(default)]
    stickers_enabled: bool,
    #[serde(default)]
    charms_enabled: bool,
    #[serde(default)]
    agents_enabled: bool,

    // Read-only v1 fields. They are migrated in memory and never serialized again.
    #[serde(default, skip_serializing)]
    default_knife_defindex: u16,
    #[serde(default, skip_serializing)]
    presets: BTreeMap<String, KnifePreset>,
    #[serde(default, skip_serializing)]
    gun_presets: BTreeMap<String, KnifePreset>,
    #[serde(default, skip_serializing)]
    glove: GlovePreset,
}

fn default_true() -> bool {
    true
}

#[derive(Deserialize)]
struct StickerCatalogEntry {
    id: u32,
}

#[derive(Deserialize)]
struct AgentCatalogEntry {
    team: String,
    model: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WeaponCosmeticPlacement {
    sticker_schema_count: u32,
    #[serde(default)]
    charm_positions: Vec<PreviewCharmPlacement>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PreviewCharmPlacement {
    placement_id: u32,
}

fn valid_sticker_ids() -> &'static BTreeSet<u32> {
    static IDS: OnceLock<BTreeSet<u32>> = OnceLock::new();
    IDS.get_or_init(|| {
        serde_json::from_str::<Vec<StickerCatalogEntry>>(include_str!("../../src/data/stickerCatalog.json"))
            .unwrap_or_default()
            .into_iter()
            .map(|entry| entry.id)
            .collect()
    })
}

fn valid_sticker_weapon_ids() -> &'static BTreeSet<u16> {
    static IDS: OnceLock<BTreeSet<u16>> = OnceLock::new();
    IDS.get_or_init(|| {
        serde_json::from_str::<Vec<StickerCatalogEntry>>(include_str!(
            "../../src/data/stickerWeaponIds.json"
        ))
        .unwrap_or_default()
        .into_iter()
        .filter_map(|entry| u16::try_from(entry.id).ok())
        .collect()
    })
}

impl Default for KnifeCustomizerConfig {
    fn default() -> Self {
        let mut shared_weapon_links = BTreeMap::new();
        for defindex in SHARED_WEAPONS {
            shared_weapon_links.insert(defindex.to_string(), true);
        }
        Self {
            schema_version: COSMETICS_SCHEMA_VERSION,
            enabled: false,
            apply_to_human_players: true,
            apply_on_pickup: true,
            music_kit_id: 0,
            loadouts: TeamLoadouts::default(),
            shared_weapon_links,
            stickers_enabled: false,
            charms_enabled: false,
            agents_enabled: false,
            default_knife_defindex: 0,
            presets: BTreeMap::new(),
            gun_presets: BTreeMap::new(),
            glove: GlovePreset::default(),
        }
    }
}

#[derive(Serialize)]
struct KnifeCustomizerState {
    plugin_present: bool,
    config_present: bool,
    cs2_running: bool,
    config: KnifeCustomizerConfig,
}

const COSMETICS_EXPORT_SCHEMA_VERSION: u8 = 2;
const LEGACY_COSMETICS_EXPORT_SCHEMA_VERSION: u8 = 1;
const COSMETICS_EXPORT_KIND: &str = "cs2bip-cosmetics-preset";
const MAX_COSMETICS_IMPORT_BYTES: u64 = 4 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct CosmeticsPresetBundle {
    schema_version: u8,
    kind: String,
    exported_at_unix: u64,
    config: KnifeCustomizerConfig,
}

#[derive(Serialize)]
struct CosmeticsPresetExportResult {
    path: String,
    size_bytes: u64,
}

#[derive(Serialize)]
struct CosmeticsPresetImportResult {
    state: KnifeCustomizerState,
    backup_path: Option<String>,
}

fn legacy_config_path(app: &AppHandle) -> Result<PathBuf> {
    let dir = app
        .path()
        .app_config_dir()
        .map_err(|e| AppError::io(e.to_string()))?;
    fs::create_dir_all(&dir)?;
    Ok(dir.join("config.json"))
}

fn config_path() -> Result<PathBuf> {
    app_storage::panel_config_path()
}

fn read_config(app: &AppHandle) -> Result<AppConfig> {
    let path = config_path()?;
    if !path.is_file() {
        let legacy = legacy_config_path(app)?;
        if legacy.is_file() {
            let config: AppConfig = serde_json::from_str(&fs::read_to_string(&legacy)?)?;
            let config = prepare_legacy_config_for_portable_state(config);
            write_json_atomic(&path, &config)?;
            if let Ok(root) = app_storage::root() {
                logging::append(&root, "INFO", "config.migrated", &legacy.to_string_lossy());
            }
            return Ok(config);
        }
    }
    if !path.exists() {
        return Ok(AppConfig::default());
    }
    let mut config: AppConfig = serde_json::from_str(&fs::read_to_string(path)?)?;
    apply_release_feature_gates(&mut config);
    Ok(config)
}

fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(value)?;
    atomic_fs::write_replace(path, &bytes).map_err(AppError::transaction_io)
}

fn write_config(_app: &AppHandle, config: &AppConfig) -> Result<()> {
    let mut config = config.clone();
    apply_release_feature_gates(&mut config);
    write_json_atomic(&config_path()?, &config)
}

fn cs2_running() -> bool {
    inspect_cs2_process(None).running
}

fn valid_agent_models(team: WeaponSide) -> &'static BTreeSet<String> {
    static CT: OnceLock<BTreeSet<String>> = OnceLock::new();
    static T: OnceLock<BTreeSet<String>> = OnceLock::new();
    let expected = if team == WeaponSide::Ct { "ct" } else { "t" };
    let target = if team == WeaponSide::Ct { &CT } else { &T };
    target.get_or_init(|| {
        serde_json::from_str::<Vec<AgentCatalogEntry>>(include_str!("../../src/data/agentCatalog.json"))
            .unwrap_or_default()
            .into_iter()
            .filter(|entry| entry.team == expected)
            .map(|entry| entry.model)
            .collect()
    })
}

fn cosmetic_placements() -> &'static BTreeMap<u16, WeaponCosmeticPlacement> {
    static PLACEMENTS: OnceLock<BTreeMap<u16, WeaponCosmeticPlacement>> = OnceLock::new();
    PLACEMENTS.get_or_init(|| {
        serde_json::from_str::<BTreeMap<u16, WeaponCosmeticPlacement>>(include_str!(
            "../../src/data/cosmeticPlacements.json"
        ))
        .unwrap_or_default()
    })
}

fn valid_charm_ids() -> &'static BTreeSet<u32> {
    static IDS: OnceLock<BTreeSet<u32>> = OnceLock::new();
    IDS.get_or_init(|| {
        serde_json::from_str::<Vec<StickerCatalogEntry>>(include_str!(
            "../../src/data/charmCatalog.json"
        ))
        .unwrap_or_default()
        .into_iter()
        .map(|entry| entry.id)
        .collect()
    })
}

#[tauri::command]
fn get_cs2_process(csgo: Option<String>) -> Result<Cs2ProcessInfo> {
    let selected = csgo.as_deref().map(csgo_path).transpose()?;
    Ok(inspect_cs2_process(selected.as_deref()))
}

fn ensure_target_not_running(root: &Path) -> Result<()> {
    let process = inspect_cs2_process(Some(root));
    if blocks_target_write(&process) {
        let detail = match (&process.executable, process.path_accessible) {
            (Some(path), _) => format!("Close CS2 before modifying this installation (PID {}, {path})", process.pid.unwrap_or_default()),
            (_, false) => "A running cs2.exe could not be matched to an installation. Close CS2, then try again".to_string(),
            _ => "Close CS2 before modifying this installation".to_string(),
        };
        return Err(AppError::process(detail));
    }
    Ok(())
}

fn ensure_steam_app_idle(root: &Path) -> Result<()> {
    steam::wait_for_app_730_idle(root, Duration::from_secs(15)).map_err(|detail| {
        AppError::transaction(format!(
            "Steam is modifying CS2 files. Pause the App 730 update or verification, wait for Steam activity to finish, then retry installation. {detail}"
        ))
    })?;
    Ok(())
}

fn valid_csgo(path: &Path) -> bool {
    path.join("gameinfo.gi").is_file() && path.join("cfg").is_dir()
}

fn normalize_windows_canonical(path: PathBuf) -> PathBuf {
    let raw = path.to_string_lossy();
    if let Some(value) = raw.strip_prefix(r"\\?\UNC\") {
        return PathBuf::from(format!(r"\\{value}"));
    }
    if let Some(value) = raw.strip_prefix(r"\\?\") {
        return PathBuf::from(value);
    }
    path
}

fn csgo_path(raw: &str) -> Result<PathBuf> {
    let selected = PathBuf::from(raw.trim().trim_matches('"'));
    let candidates = [
        selected.clone(),
        selected.join("game").join("csgo"),
        selected.join("csgo"),
    ];
    for candidate in candidates {
        if valid_csgo(&candidate) {
            let canonical = fs::canonicalize(&candidate).map_err(|error| {
                AppError::directory(format!(
                    "Cannot resolve the selected CS2 directory ({}): {error}",
                    candidate.display()
                ))
            })?;
            return Ok(normalize_windows_canonical(canonical));
        }
    }
    Err(AppError::directory(format!(
        "The selected path is not a CS2 installation root, game directory, or game/csgo directory: {}",
        selected.display()
    )))
}

fn cfg_paths(csgo: &Path) -> [PathBuf; 2] {
    // The quick-knife bind is still stored in the shipped gameplay cfgs; the
    // cosmetics payload keeps those files, so this stays their single writer.
    [
        csgo.join("cfg/my_bot_normal_config.cfg"),
        csgo.join("cfg/my_bot_ffa_config.cfg"),
    ]
}

fn cfg_files_present(csgo: &Path) -> bool {
    cfg_paths(csgo).iter().all(|path| path.is_file())
}

fn replace_managed_cfg_command(csgo: &Path, command: &str, replacement: &str) -> Result<()> {
    for path in cfg_paths(csgo) {
        replace_cfg_command(&path, command, replacement)?;
    }
    Ok(())
}

fn replace_cfg_command(path: &Path, command: &str, replacement: &str) -> Result<()> {
    let text = fs::read_to_string(path)?;
    let mut found = false;
    let mut lines = Vec::new();
    for line in text.lines() {
        if line.trim_start().starts_with(command) {
            if !found {
                lines.push(replacement.to_string());
                found = true;
            }
        } else {
            lines.push(line.to_string());
        }
    }
    if !found {
        lines.push(replacement.to_string());
    }
    fs::write(path, format!("{}\r\n", lines.join("\r\n")))?;
    Ok(())
}

#[tauri::command]
fn get_config(app: AppHandle) -> Result<AppConfig> {
    read_config(&app)
}

#[tauri::command]
fn save_config(app: AppHandle, config: AppConfig) -> Result<()> {
    let current = read_config(&app)?;
    if cs2_running()
        && (current.experimental_features_enabled != config.experimental_features_enabled
            || current.experimental_stickers_enabled != config.experimental_stickers_enabled)
    {
        return Err(AppError::process(
            "Close CS2 before changing experimental feature settings",
        ));
    }
    write_config(&app, &config)
}

#[tauri::command]
fn should_present_welcome_story() -> bool {
    welcome_story_release_eligible(cfg!(not(debug_assertions)), app_version::display())
}

#[tauri::command]
fn detect_directories(app: AppHandle) -> Result<DirectoryInfo> {
    let mut config = read_config(&app)?;
    let mut candidates = Vec::new();
    if let Some(path) = &config.csgo_path {
        if let Ok(resolved) = csgo_path(path) {
            candidates.push(resolved.to_string_lossy().into_owned());
        }
    }
    for path in steam::detect_cs2_directories() {
        let path = path.to_string_lossy().into_owned();
        if !candidates
            .iter()
            .any(|candidate| steam::paths_equal(Path::new(candidate), Path::new(&path)))
        {
            candidates.push(path);
        }
    }
    let saved = config
        .csgo_path
        .clone()
        .filter(|p| valid_csgo(Path::new(p)));
    let selected = saved.or_else(|| (candidates.len() == 1).then(|| candidates[0].clone()));
    if selected.is_some() && config.csgo_path != selected {
        config.csgo_path = selected.clone();
        write_config(&app, &config)?;
    }
    Ok(DirectoryInfo {
        valid: selected.is_some(),
        needs_choice: candidates.len() > 1 && selected.is_none(),
        steam_found: !candidates.is_empty(),
        candidates,
        selected,
    })
}

#[tauri::command]
fn select_directory(app: AppHandle, path: String) -> Result<DirectoryInfo> {
    let resolved = csgo_path(&path)?.to_string_lossy().into_owned();
    let mut config = read_config(&app)?;
    config.csgo_path = Some(resolved);
    write_config(&app, &config)?;
    detect_directories(app)
}

/// The payload shipped next to the Panel executable. There is no online update
/// channel, so this is the only location the installer ever reads from.
fn payload_root() -> Result<PathBuf> {
    let executable =
        std::env::current_exe().map_err(|error| AppError::payload(error.to_string()))?;
    executable
        .parent()
        .map(Path::to_path_buf)
        .ok_or_else(|| AppError::payload("Panel executable has no parent directory"))
}

fn local_state_root(_app: &AppHandle) -> Result<PathBuf> {
    app_storage::root()
}

#[tauri::command]
fn get_panel_memory() -> Result<app_storage::UiMemory> {
    app_storage::read_ui_memory()
}

#[tauri::command]
fn save_panel_memory(entries: BTreeMap<String, String>) -> Result<app_storage::UiMemory> {
    app_storage::write_ui_memory(entries)
}

#[tauri::command]
fn record_panel_error(error: PanelErrorRecord) -> Result<()> {
    let root = app_storage::root()?;
    let detail = format!(
        "{} [{}] {} | {}",
        error.code,
        error.category,
        error.detail,
        error.context.unwrap_or_else(|| "no-context".to_string())
    );
    logging::append(&root, "ERROR", "panel.error", &detail);
    Ok(())
}

fn validate_files_at(
    app: Option<&AppHandle>,
    root: &Path,
    verify_hashes: bool,
) -> Result<FilesReport> {
    if let Some(app) = app {
        if let (Ok(payload), Ok(state)) = (payload_root(), local_state_root(app)) {
            let inspection = if verify_hashes {
                installer::inspect(&payload, &state, root)
            } else {
                installer::inspect_quick(&payload, &state, root)
            };
            if let Ok(inspection) = inspection {
                if inspection.total > 0 {
                    let mut missing = inspection.missing;
                    missing.extend(
                        inspection
                            .corrupt
                            .into_iter()
                            .map(|path| format!("{path} (hash mismatch)")),
                    );
                    return Ok(FilesReport {
                        ok: missing.is_empty(),
                        total: inspection.total,
                        present: inspection.healthy,
                        missing,
                        misplaced: None,
                    });
                }
            }
        }
    }
    let required = [
        "gameinfo.gi",
        "cfg/my_bot_normal_config.cfg",
        "cfg/my_bot_ffa_config.cfg",
        "addons/metamod/counterstrikesharp.vdf",
        "addons/metamod/bin/win64/server.dll",
        "addons/counterstrikesharp/bin/win64/counterstrikesharp.dll",
        "addons/counterstrikesharp/dotnet/dotnet.exe",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.dll",
    ];
    let missing: Vec<String> = required
        .iter()
        .filter(|p| !root.join(p).is_file())
        .map(|p| p.to_string())
        .collect();
    Ok(FilesReport {
        ok: missing.is_empty(),
        total: required.len(),
        present: required.len() - missing.len(),
        missing,
        misplaced: None,
    })
}

#[tauri::command]
fn validate_files(app: AppHandle, csgo: String) -> Result<FilesReport> {
    let root = csgo_path(&csgo)?;
    validate_files_at(Some(&app), &root, true)
}

fn find_steam_executable() -> Result<PathBuf> {
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    if let Some(path) = system
        .processes()
        .values()
        .find(|process| process.name().eq_ignore_ascii_case("steam.exe"))
        .and_then(|process| process.exe())
        .filter(|path| path.is_file())
    {
        return Ok(path.to_path_buf());
    }

    let mut candidates = Vec::new();
    for variable in ["ProgramFiles(x86)", "ProgramFiles"] {
        if let Some(root) = std::env::var_os(variable) {
            candidates.push(PathBuf::from(root).join("Steam/Steam.exe"));
        }
    }
    candidates.push(PathBuf::from(r"C:\Program Files (x86)\Steam\Steam.exe"));

    candidates
        .into_iter()
        .find(|path| path.is_file())
        .ok_or_else(|| AppError::launch("Steam.exe was not found. Start Steam, then try again"))
}

/// Start the game through Steam for one explicit local-cosmetics window. The
/// project search path only exists between this call and the runtime going away
/// again, so a CS2 started straight from Steam stays vanilla.
fn spawn_local_launch(
    prepared: &PreparedLaunch,
    state_root: &Path,
    target: &Path,
    spawn: impl FnOnce(&[&'static str]) -> std::io::Result<()>,
) -> Result<LaunchResult> {
    match spawn(&prepared.arguments) {
        Ok(()) => Ok(LaunchResult {
            options: prepared.options.clone(),
            insecure: prepared.insecure,
        }),
        Err(error) => {
            let detail = format!("Steam could not launch local cosmetics mode: {error}");
            match launch_isolation::restore_clean(state_root, target) {
                Ok(_) => Err(AppError::launch(detail)),
                Err(restore) => {
                    logging::append(
                        state_root,
                        "ERROR",
                        "launch.isolation_restore_failed",
                        &format!("{detail}; {}", restore.detail),
                    );
                    Err(restore)
                }
            }
        }
    }
}

#[tauri::command]
fn get_launch_isolation(csgo: String) -> Result<launch_isolation::IsolationStatus> {
    let root = csgo_path(&csgo)?;
    launch_isolation::isolation_status(
        &app_storage::root()?,
        &root,
        launch_isolation::unix_now(),
    )
}

#[tauri::command]
fn launch_local_cosmetics(app: AppHandle) -> Result<LaunchResult> {
    let config = read_config(&app)?;
    let configured_path = config.csgo_path.as_deref().ok_or_else(|| {
        AppError::directory("Select the CS2 game/csgo directory before launching")
    })?;
    let root = csgo_path(configured_path)?;
    ensure_target_not_running(&root)?;
    let state = local_state_root(&app)?;
    let now = launch_isolation::unix_now();
    // Heal an interrupted transaction before arming a new one.
    launch_isolation::recover(&state, &root, false, now)?;
    let prepared = launch_isolation::prepare_local_launch(&state, &root, now)?;
    let steam = match find_steam_executable() {
        Ok(steam) => steam,
        Err(error) => {
            let _ = launch_isolation::restore_clean(&state, &root);
            return Err(error);
        }
    };
    let result = spawn_local_launch(&prepared, &state, &root, |arguments| {
        Command::new(&steam).args(arguments).spawn().map(|_| ())
    });
    logging::append(
        &state,
        if result.is_ok() { "INFO" } else { "ERROR" },
        "panel.launch_local_cosmetics",
        &format!("target={}, options={}", root.display(), prepared.options),
    );
    result
}

#[tauri::command]
fn run_install_checks(app: AppHandle, csgo: String) -> Result<InstallCheckReport> {
    let root = csgo_path(&csgo)?;
    collect_install_checks(&payload_root()?, &local_state_root(&app)?, &root)
}

fn collect_install_checks(payload: &Path, state: &Path, root: &Path) -> Result<InstallCheckReport> {
    let process = inspect_cs2_process(Some(root));
    let report = install_checks::run(payload, state, root, process.running)?;
    let report_path = install_checks::persist(state, &report)?;
    logging::append(
        state,
        if report.can_proceed { "INFO" } else { "ERROR" },
        "install.preflight",
        &format!(
            "target={}, pass={}, warn={}, fail={}, blocking_fail={}, can_proceed={}, report={}",
            report.target,
            report.pass_count,
            report.warn_count,
            report.fail_count,
            report.blocking_fail_count,
            report.can_proceed,
            report_path.display()
        ),
    );
    for check in report.checks.iter().filter(|check| check.status != install_checks::CheckStatus::Pass) {
        logging::append(
            state,
            if check.status == install_checks::CheckStatus::Fail { "ERROR" } else { "WARN" },
            "install.preflight.item",
            &format!(
                "code={}, blocking={}, title={}, evidence={}, cause={}, action={}",
                check.code, check.blocking, check.title, check.evidence, check.cause, check.action
            ),
        );
    }
    Ok(report)
}

fn ensure_install_checks_pass(report: &InstallCheckReport) -> Result<()> {
    if report.can_proceed {
        return Ok(());
    }
    let detail = report.checks.iter()
        .filter(|check| check.blocking && check.status == install_checks::CheckStatus::Fail)
        .map(|check| format!("{} {}: {}", check.code, check.title, check.action))
        .collect::<Vec<_>>()
        .join(" | ");
    Err(AppError::preflight(format!(
        "Installation preflight found {} blocking error(s). {detail}",
        report.blocking_fail_count
    )))
}

#[tauri::command]
fn get_drop_knives(app: AppHandle, csgo: String) -> Result<DropKnivesState> {
    let root = csgo_path(&csgo)?;
    let config = read_config(&app)?;
    Ok(drop_knives_at(
        &root,
        &config,
        inspect_cs2_process(Some(&root)).running,
    ))
}

fn drop_knives_at(root: &Path, config: &AppConfig, running: bool) -> DropKnivesState {
    DropKnivesState {
        bind_key: config.drop_knife_bind.clone(),
        selected: config.drop_knife_subclasses.clone(),
        cfg_present: cfg_files_present(root),
        cs2_running: running,
    }
}

#[tauri::command]
fn set_drop_knives(
    app: AppHandle,
    csgo: String,
    bind_key: String,
    selected: Vec<u16>,
) -> Result<DropKnivesState> {
    let root = csgo_path(&csgo)?;
    let commands = selected
        .iter()
        .map(|id| format!("subclass_create {id}"))
        .collect::<Vec<_>>()
        .join(";");
    let line = format!("bind {bind_key} \"{commands}\"");
    replace_managed_cfg_command(&root, "bind ", &line)?;
    let mut config = read_config(&app)?;
    config.drop_knife_bind = bind_key;
    config.drop_knife_subclasses = selected;
    write_config(&app, &config)?;
    get_drop_knives(app, csgo)
}

fn knife_config_path(root: &Path) -> PathBuf {
    root.join("addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json")
}

fn gun_config_path(root: &Path) -> PathBuf {
    root.join("addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_gun_presets.json")
}

fn normalize_preset(preset: &mut KnifePreset) {
    preset.seed = preset.seed.clamp(0, 1000);
    preset.wear = preset.wear.clamp(0.0, 1.0);
    preset.stattrak_count = preset.stattrak_count.max(0);
    preset.name_tag = preset.name_tag.chars().take(20).collect();
    if preset.souvenir_enabled {
        preset.stattrak_enabled = false;
    }
}

fn normalize_stickers(defindex: u16, stickers: &mut Vec<StickerPreset>) -> Result<()> {
    if stickers.len() > 5 {
        return Err(AppError::invalid("A weapon cannot have more than five stickers"));
    }
    let placement = cosmetic_placements().get(&defindex);
    if !stickers.is_empty() && (!valid_sticker_weapon_ids().contains(&defindex) || placement.is_none()) {
        return Err(AppError::invalid("Stickers are not supported for this weapon"));
    }
    let valid_ids = valid_sticker_ids();
    let mut slots = BTreeSet::new();
    for sticker in stickers.iter_mut() {
        if sticker.slot > 4 || !slots.insert(sticker.slot) {
            return Err(AppError::invalid("Sticker slots must be unique and between 0 and 4"));
        }
        if sticker.id == 0 || !valid_ids.contains(&sticker.id) {
            return Err(AppError::invalid("Unknown sticker id"));
        }
        if sticker.schema >= placement.map_or(0, |entry| entry.sticker_schema_count) {
            return Err(AppError::invalid("Sticker schema is not supported for this weapon"));
        }
        if !sticker.wear.is_finite()
            || !sticker.scale.is_finite()
            || !sticker.rotation.is_finite()
            || !sticker.offset_x.is_finite()
            || !sticker.offset_y.is_finite()
            || !(0.0..=1.0).contains(&sticker.wear)
            || !(0.1..=2.0).contains(&sticker.scale)
            || !(0.0..=360.0).contains(&sticker.rotation)
            || !(-1.0..=1.0).contains(&sticker.offset_x)
            || !(-1.0..=1.0).contains(&sticker.offset_y)
        {
            return Err(AppError::invalid("Sticker values are outside the supported range"));
        }
    }
    stickers.sort_by_key(|sticker| sticker.slot);
    Ok(())
}

fn normalize_charm(defindex: u16, charm: &mut Option<CharmPreset>) -> Result<()> {
    let Some(charm) = charm else {
        return Ok(());
    };
    let placement = cosmetic_placements()
        .get(&defindex)
        .ok_or_else(|| AppError::invalid("Charms are not supported for this weapon"))?;
    if !valid_charm_ids().contains(&charm.id) {
        return Err(AppError::invalid("Unknown charm id"));
    }
    if !(0..=i32::MAX).contains(&charm.seed) {
        return Err(AppError::invalid("Charm seed is outside the supported range"));
    }
    if !placement
        .charm_positions
        .iter()
        .any(|entry| entry.placement_id == charm.placement_id)
    {
        return Err(AppError::invalid("Charm placement is not supported for this weapon"));
    }
    Ok(())
}

fn sanitize_preset_decorations(
    preset: &mut serde_json::Value,
    allow_decorations: bool,
    defindex: Option<u16>,
    migrate_schema: bool,
) -> bool {
    let Some(object) = preset.as_object_mut() else {
        return false;
    };
    let mut changed = false;
    if let Some(value) = object.get_mut("stickers") {
        if migrate_schema && allow_decorations {
            if let (Some(_), Some(stickers), Some(capability)) = (
                defindex,
                value.as_array_mut(),
                defindex.and_then(|id| cosmetic_placements().get(&id)),
            ) {
                for sticker in stickers {
                    let Some(sticker) = sticker.as_object_mut() else { continue };
                    if sticker.contains_key("schema") { continue; }
                    let slot = sticker.get("slot").and_then(serde_json::Value::as_u64).unwrap_or(0);
                    let schema = slot.min(capability.sticker_schema_count.saturating_sub(1) as u64);
                    sticker.insert("schema".into(), serde_json::Value::from(schema));
                    changed = true;
                }
            }
        }
        let valid = allow_decorations
            && defindex.is_some()
            && serde_json::from_value::<Vec<StickerPreset>>(value.clone())
                .ok()
                .is_some_and(|mut stickers| normalize_stickers(defindex.unwrap(), &mut stickers).is_ok());
        if !valid && !value.as_array().is_some_and(|entries| entries.is_empty() && !allow_decorations) {
            *value = serde_json::Value::Array(Vec::new());
            changed = true;
        }
    }
    if let Some(value) = object.get_mut("charm") {
        let valid = allow_decorations
            && defindex.is_some()
            && (value.is_null()
                || serde_json::from_value::<CharmPreset>(value.clone())
                    .ok()
                    .is_some_and(|charm| normalize_charm(defindex.unwrap(), &mut Some(charm)).is_ok()));
        if !valid && !value.is_null() {
            *value = serde_json::Value::Null;
            changed = true;
        }
    }
    changed
}

fn sanitize_preset_map(value: Option<&mut serde_json::Value>, allow_decorations: bool, migrate_schema: bool) -> bool {
    let Some(map) = value.and_then(serde_json::Value::as_object_mut) else {
        return false;
    };
    map.iter_mut().fold(false, |changed, (defindex, preset)| {
        sanitize_preset_decorations(preset, allow_decorations, defindex.parse().ok(), migrate_schema) || changed
    })
}

fn sanitize_knife_config_decorations(value: &mut serde_json::Value, schema: Option<u64>) -> bool {
    let Some(root) = value.as_object_mut() else {
        return false;
    };
    let migrate_schema = schema.is_none_or(|version| version < COSMETICS_SCHEMA_VERSION as u64);
    let mut changed = sanitize_preset_map(root.get_mut("presets"), false, migrate_schema)
        | sanitize_preset_map(root.get_mut("gun_presets"), true, migrate_schema);
    let Some(loadouts) = root
        .get_mut("loadouts")
        .and_then(serde_json::Value::as_object_mut)
    else {
        return changed;
    };
    for side in ["ct", "t"] {
        let Some(team) = loadouts
            .get_mut(side)
            .and_then(serde_json::Value::as_object_mut)
        else {
            continue;
        };
        changed |= sanitize_preset_map(team.get_mut("knife_presets"), false, migrate_schema);
        changed |= sanitize_preset_map(team.get_mut("gun_presets"), true, migrate_schema);
    }
    changed
}

fn sanitize_team_gun_decorations(value: &mut serde_json::Value, schema: Option<u64>) -> bool {
    let migrate_schema = schema.is_none_or(|version| version < COSMETICS_SCHEMA_VERSION as u64);
    if matches!(schema, Some(2) | Some(3) | Some(4) | Some(5)) {
        let Some(root) = value.as_object_mut() else {
            return false;
        };
        sanitize_preset_map(root.get_mut("ct"), true, migrate_schema)
            | sanitize_preset_map(root.get_mut("t"), true, migrate_schema)
    } else {
        sanitize_preset_map(Some(value), true, migrate_schema)
    }
}

fn normalize_team_loadout(team: WeaponSide, loadout: &mut TeamLoadout) -> Result<()> {
    if !loadout.agent_model.is_empty() && !valid_agent_models(team).contains(&loadout.agent_model) {
        return Err(AppError::invalid("Invalid agent model for team"));
    }
    for (def, preset) in &mut loadout.knife_presets {
        let defindex: u16 = def
            .parse()
            .map_err(|_| AppError::invalid("Invalid knife defindex"))?;
        if !(500..=526).contains(&defindex) || preset.paint <= 0 {
            return Err(AppError::invalid("Invalid knife preset"));
        }
        if !preset.stickers.is_empty() || preset.charm.is_some() {
            return Err(AppError::invalid("Knife stickers and charms are not supported"));
        }
        normalize_preset(preset);
    }
    for (def, preset) in &mut loadout.gun_presets {
        let defindex: u16 = def
            .parse()
            .map_err(|_| AppError::invalid("Invalid gun defindex"))?;
        if defindex == 0 || defindex >= 500 || preset.paint <= 0 {
            return Err(AppError::invalid("Invalid gun preset"));
        }
        if (team == WeaponSide::Ct && weapon_side(defindex) == WeaponSide::T)
            || (team == WeaponSide::T && weapon_side(defindex) == WeaponSide::Ct)
        {
            return Err(AppError::invalid(
                "Weapon preset is stored under the wrong team",
            ));
        }
        normalize_preset(preset);
        normalize_stickers(defindex, &mut preset.stickers)?;
        normalize_charm(defindex, &mut preset.charm)?;
    }
    if loadout.default_knife_defindex != 0
        && !loadout
            .knife_presets
            .contains_key(&loadout.default_knife_defindex.to_string())
    {
        return Err(AppError::invalid("Default knife has no saved preset"));
    }
    loadout.glove.seed = loadout.glove.seed.clamp(0, 1000);
    loadout.glove.wear = loadout.glove.wear.clamp(0.0, 1.0);
    if loadout.glove.enabled && loadout.glove.defindex == 0 && loadout.glove.paint == 0 {
        loadout.glove = GlovePreset {
            enabled: true,
            ..GlovePreset::default()
        };
    }
    if loadout.glove.enabled
        && (!(4725..=5035).contains(&loadout.glove.defindex) || loadout.glove.paint <= 0)
    {
        return Err(AppError::invalid("Invalid glove preset"));
    }
    Ok(())
}

fn ensure_shared_link_defaults(config: &mut KnifeCustomizerConfig) {
    for defindex in SHARED_WEAPONS {
        config
            .shared_weapon_links
            .entry(defindex.to_string())
            .or_insert(true);
    }
}

fn apply_legacy_guns(config: &mut KnifeCustomizerConfig, guns: BTreeMap<String, KnifePreset>) {
    config.loadouts.ct.gun_presets.clear();
    config.loadouts.t.gun_presets.clear();
    for (key, preset) in guns {
        let Ok(defindex) = key.parse::<u16>() else {
            continue;
        };
        match weapon_side(defindex) {
            WeaponSide::Ct => {
                config.loadouts.ct.gun_presets.insert(key, preset);
            }
            WeaponSide::T => {
                config.loadouts.t.gun_presets.insert(key, preset);
            }
            WeaponSide::Shared => {
                config
                    .loadouts
                    .ct
                    .gun_presets
                    .insert(key.clone(), preset.clone());
                config.loadouts.t.gun_presets.insert(key.clone(), preset);
                config.shared_weapon_links.insert(key, true);
            }
        }
    }
}

fn migrate_legacy_config(config: &mut KnifeCustomizerConfig) {
    if config.schema_version >= COSMETICS_SCHEMA_VERSION {
        ensure_shared_link_defaults(config);
        return;
    }
    if matches!(config.schema_version, 2 | 3 | 4) {
        if config.schema_version == 2 {
            config.stickers_enabled = false;
        }
        if config.schema_version < 4 {
            config.charms_enabled = false;
        }
        config.schema_version = COSMETICS_SCHEMA_VERSION;
        config.agents_enabled = false;
        ensure_shared_link_defaults(config);
        return;
    }
    let legacy_guns = std::mem::take(&mut config.gun_presets);
    let legacy_loadout = TeamLoadout {
        agent_model: String::new(),
        default_knife_defindex: config.default_knife_defindex,
        knife_presets: std::mem::take(&mut config.presets),
        glove: std::mem::take(&mut config.glove),
        gun_presets: BTreeMap::new(),
    };
    config.loadouts.ct = legacy_loadout.clone();
    config.loadouts.t = legacy_loadout;
    config.schema_version = COSMETICS_SCHEMA_VERSION;
    apply_legacy_guns(config, legacy_guns);
    ensure_shared_link_defaults(config);
}

fn read_knife_config(root: &Path) -> Result<KnifeCustomizerConfig> {
    let path = knife_config_path(root);
    let mut needs_migration = false;
    let mut config = if path.is_file() {
        let text = fs::read_to_string(&path)?;
        let mut value: serde_json::Value = serde_json::from_str(&text)?;
        let source_schema = value
            .get("schema_version")
            .and_then(serde_json::Value::as_u64);
        needs_migration = source_schema != Some(COSMETICS_SCHEMA_VERSION as u64);
        needs_migration |= sanitize_knife_config_decorations(&mut value, source_schema);
        serde_json::from_value(value)?
    } else {
        KnifeCustomizerConfig::default()
    };
    migrate_legacy_config(&mut config);

    let gun_path = gun_config_path(root);
    if gun_path.is_file() {
        let text = fs::read_to_string(&gun_path)?;
        let mut value: serde_json::Value = serde_json::from_str(&text)?;
        let gun_schema = value
            .get("schema_version")
            .and_then(serde_json::Value::as_u64);
        needs_migration |= sanitize_team_gun_decorations(&mut value, gun_schema);
        if matches!(gun_schema, Some(2) | Some(3) | Some(4) | Some(5)) {
            let guns: TeamGunConfig = serde_json::from_value(value)?;
            config.loadouts.ct.gun_presets = guns.ct;
            config.loadouts.t.gun_presets = guns.t;
            config.shared_weapon_links = guns.shared_weapon_links;
            needs_migration |= gun_schema != Some(COSMETICS_SCHEMA_VERSION as u64);
        } else {
            apply_legacy_guns(&mut config, serde_json::from_value(value)?);
            needs_migration = true;
        }
    }
    ensure_shared_link_defaults(&mut config);
    if needs_migration {
        save_knife_config(root, &mut config)?;
    }
    Ok(config)
}

fn normalize_knife_config(config: &mut KnifeCustomizerConfig) -> Result<()> {
    migrate_legacy_config(config);
    config.schema_version = COSMETICS_SCHEMA_VERSION;
    config.stickers_enabled = STICKER_RELEASE_ENABLED && config.stickers_enabled;
    config.charms_enabled = STICKER_RELEASE_ENABLED && config.charms_enabled;
    config.agents_enabled = STICKER_RELEASE_ENABLED && config.agents_enabled;
    config.music_kit_id = config.music_kit_id.clamp(0, u16::MAX as i32);
    normalize_team_loadout(WeaponSide::Ct, &mut config.loadouts.ct)?;
    normalize_team_loadout(WeaponSide::T, &mut config.loadouts.t)?;
    ensure_shared_link_defaults(config);

    for (key, linked) in &config.shared_weapon_links {
        let defindex: u16 = key
            .parse()
            .map_err(|_| AppError::invalid("Invalid shared weapon defindex"))?;
        if defindex == 0 || defindex >= 500 || weapon_side(defindex) != WeaponSide::Shared {
            return Err(AppError::invalid("Invalid shared weapon link"));
        }
        if !linked {
            continue;
        }
        let ct = config.loadouts.ct.gun_presets.get(key);
        let t = config.loadouts.t.gun_presets.get(key);
        match (ct, t) {
            (Some(left), Some(right)) if !left.base_value_eq(right) => {
                return Err(AppError::invalid("Linked CT/T weapon base presets must match"));
            }
            (Some(preset), None) => {
                config
                    .loadouts
                    .t
                    .gun_presets
                    .insert(key.clone(), preset.clone_without_decorations());
            }
            (None, Some(preset)) => {
                config
                    .loadouts
                    .ct
                    .gun_presets
                    .insert(key.clone(), preset.clone_without_decorations());
            }
            _ => {}
        }
    }
    Ok(())
}

fn versioned_backup_path(path: &Path, schema_version: u64) -> PathBuf {
    let version = if schema_version <= 1 { 1 } else { schema_version };
    PathBuf::from(format!("{}.v{version}.bak", path.to_string_lossy()))
}

#[cfg(test)]
fn legacy_backup_path(path: &Path) -> PathBuf {
    versioned_backup_path(path, 1)
}

fn backup_legacy_file(path: &Path) -> Result<()> {
    if !path.is_file() {
        return Ok(());
    }
    let value: serde_json::Value = serde_json::from_str(&fs::read_to_string(path)?)?;
    let schema_version = value
        .get("schema_version")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(1);
    if schema_version == COSMETICS_SCHEMA_VERSION as u64 {
        return Ok(());
    }
    let backup = versioned_backup_path(path, schema_version);
    if !backup.exists() {
        fs::copy(path, backup)?;
    }
    Ok(())
}

fn save_knife_config(root: &Path, config: &mut KnifeCustomizerConfig) -> Result<()> {
    normalize_knife_config(config)?;
    let knife_path = knife_config_path(root);
    let gun_path = gun_config_path(root);
    backup_legacy_file(&knife_path)?;
    backup_legacy_file(&gun_path)?;
    write_json_atomic(&knife_path, config)?;
    let guns = TeamGunConfig {
        schema_version: COSMETICS_SCHEMA_VERSION,
        ct: config.loadouts.ct.gun_presets.clone(),
        t: config.loadouts.t.gun_presets.clone(),
        shared_weapon_links: config.shared_weapon_links.clone(),
    };
    write_json_atomic(&gun_path, &guns)
}

fn sticker_configuration(config: &KnifeCustomizerConfig) -> BTreeMap<String, Vec<StickerPreset>> {
    let mut result = BTreeMap::new();
    for (side, loadout) in [("ct", &config.loadouts.ct), ("t", &config.loadouts.t)] {
        for (kind, presets) in [("knife", &loadout.knife_presets), ("gun", &loadout.gun_presets)] {
            for (defindex, preset) in presets {
                if !preset.stickers.is_empty() {
                    result.insert(format!("{side}:{kind}:{defindex}"), preset.stickers.clone());
                }
            }
        }
    }
    result
}

fn charm_configuration(config: &KnifeCustomizerConfig) -> BTreeMap<String, CharmPreset> {
    let mut result = BTreeMap::new();
    for (side, loadout) in [("ct", &config.loadouts.ct), ("t", &config.loadouts.t)] {
        for (defindex, preset) in &loadout.gun_presets {
            if let Some(charm) = &preset.charm {
                result.insert(format!("{side}:gun:{defindex}"), charm.clone());
            }
        }
    }
    result
}

fn sticker_configuration_changed(left: &KnifeCustomizerConfig, right: &KnifeCustomizerConfig) -> bool {
    left.stickers_enabled != right.stickers_enabled
        || left.charms_enabled != right.charms_enabled
        || left.agents_enabled != right.agents_enabled
        || left.loadouts.ct.agent_model != right.loadouts.ct.agent_model
        || left.loadouts.t.agent_model != right.loadouts.t.agent_model
        || sticker_configuration(left) != sticker_configuration(right)
        || charm_configuration(left) != charm_configuration(right)
}

fn explicit_json_path(value: &str, operation: &str) -> Result<PathBuf> {
    let path = PathBuf::from(value);
    if path.extension().and_then(|value| value.to_str()).is_none_or(|value| !value.eq_ignore_ascii_case("json")) {
        return Err(AppError::invalid(format!("{operation} path must use the .json extension")));
    }
    if path.file_name().is_none() {
        return Err(AppError::invalid(format!("{operation} path has no file name")));
    }
    Ok(path)
}

fn backup_cosmetics_before_import(root: &Path) -> Result<Option<PathBuf>> {
    let sources = [knife_config_path(root), gun_config_path(root)];
    if !sources.iter().any(|path| path.is_file()) {
        return Ok(None);
    }
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
    let directory = root.join(".csbip").join("cosmetics-backups").join(format!("pre-import-{stamp}"));
    fs::create_dir_all(&directory)?;
    for source in sources.into_iter().filter(|path| path.is_file()) {
        let destination = directory.join(source.file_name().unwrap_or_default());
        fs::copy(source, destination)?;
    }
    Ok(Some(directory))
}

fn export_cosmetics_preset_at(root: &Path, destination: &Path) -> Result<CosmeticsPresetExportResult> {
    let parent = destination.parent().ok_or_else(|| AppError::invalid("Export path has no parent directory"))?;
    if !parent.is_dir() {
        return Err(AppError::invalid("Export destination directory does not exist"));
    }
    let mut config = read_knife_config(&root)?;
    normalize_knife_config(&mut config)?;
    let bundle = CosmeticsPresetBundle {
        schema_version: COSMETICS_EXPORT_SCHEMA_VERSION,
        kind: COSMETICS_EXPORT_KIND.into(),
        exported_at_unix: SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs(),
        config,
    };
    let bytes = serde_json::to_vec_pretty(&bundle)?;
    atomic_fs::write_replace(&destination, &bytes)?;
    Ok(CosmeticsPresetExportResult {
        path: destination.to_string_lossy().into_owned(),
        size_bytes: bytes.len() as u64,
    })
}

fn read_cosmetics_preset(source: &Path) -> Result<KnifeCustomizerConfig> {
    let metadata = fs::metadata(&source)?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_COSMETICS_IMPORT_BYTES {
        return Err(AppError::invalid("Cosmetics preset must be a non-empty JSON file no larger than 4 MiB"));
    }
    let mut bundle: CosmeticsPresetBundle = serde_json::from_slice(&fs::read(&source)?)?;
    if !matches!(bundle.schema_version, LEGACY_COSMETICS_EXPORT_SCHEMA_VERSION | COSMETICS_EXPORT_SCHEMA_VERSION)
        || bundle.kind != COSMETICS_EXPORT_KIND
    {
        return Err(AppError::invalid("Unsupported cosmetics preset schema or file type"));
    }
    normalize_knife_config(&mut bundle.config)?;
    Ok(bundle.config)
}

fn snapshot_cosmetics_files(root: &Path) -> Result<Vec<(PathBuf, Option<Vec<u8>>)>> {
    [knife_config_path(root), gun_config_path(root)]
        .into_iter()
        .map(|path| {
            let bytes = if path.is_file() { Some(fs::read(&path)?) } else { None };
            Ok((path, bytes))
        })
        .collect()
}

fn restore_cosmetics_files(snapshot: &[(PathBuf, Option<Vec<u8>>)]) -> Result<()> {
    for (path, bytes) in snapshot {
        match bytes {
            Some(bytes) => atomic_fs::write_replace(path, bytes).map_err(AppError::transaction_io)?,
            None if path.exists() => fs::remove_file(path).map_err(AppError::transaction_io)?,
            None => {}
        }
    }
    Ok(())
}

fn import_cosmetics_preset_at<F>(root: &Path, source: &Path, after_write: F) -> Result<Option<PathBuf>>
where
    F: FnOnce() -> Result<()>,
{
    let mut config = read_cosmetics_preset(source)?;
    let snapshot = snapshot_cosmetics_files(root)?;
    let backup = backup_cosmetics_before_import(&root)?;
    if let Err(error) = save_knife_config(root, &mut config).and_then(|_| after_write()) {
        if let Err(rollback) = restore_cosmetics_files(&snapshot) {
            return Err(AppError::transaction(format!(
                "Cosmetics import failed ({}) and rollback failed ({})",
                error.detail, rollback.detail
            )));
        }
        return Err(error);
    }
    Ok(backup)
}

#[tauri::command]
fn export_cosmetics_preset(csgo: String, destination: String) -> Result<CosmeticsPresetExportResult> {
    let root = csgo_path(&csgo)?;
    let destination = explicit_json_path(&destination, "Export")?;
    export_cosmetics_preset_at(&root, &destination)
}

#[tauri::command]
fn import_cosmetics_preset(csgo: String, source: String) -> Result<CosmeticsPresetImportResult> {
    let root = csgo_path(&csgo)?;
    let source = explicit_json_path(&source, "Import")?;
    let backup = import_cosmetics_preset_at(&root, &source, || {
        app_storage::mirror_cosmetics(&root)?;
        Ok(())
    })?;
    Ok(CosmeticsPresetImportResult {
        state: get_knife_customizer(csgo)?,
        backup_path: backup.map(|path| path.to_string_lossy().into_owned()),
    })
}

#[tauri::command]
fn get_knife_customizer(csgo: String) -> Result<KnifeCustomizerState> {
    let root = csgo_path(&csgo)?;
    let path = knife_config_path(&root);
    let present = path.is_file();
    let config = read_knife_config(&root)?;
    if present {
        app_storage::mirror_cosmetics(&root)?;
    }
    Ok(KnifeCustomizerState {
        plugin_present: path.with_file_name("PlayerKnifeCustomizer.dll").is_file(),
        config_present: present,
        cs2_running: cs2_running(),
        config,
    })
}

#[tauri::command]
fn save_knife_customizer(
    csgo: String,
    mut config: KnifeCustomizerConfig,
) -> Result<KnifeCustomizerState> {
    let root = csgo_path(&csgo)?;
    if blocks_target_write(&inspect_cs2_process(Some(&root))) {
        let current = read_knife_config(&root)?;
        if sticker_configuration_changed(&current, &config) {
            return Err(AppError::process(
                "Close CS2 before changing or saving sticker configuration",
            ));
        }
    }
    save_knife_config(&root, &mut config)?;
    app_storage::mirror_cosmetics(&root)?;
    get_knife_customizer(csgo)
}

#[tauri::command]
async fn get_runtime_snapshot(app: AppHandle) -> Result<RuntimeSnapshot> {
    run_installation_task("Runtime snapshot", move || get_runtime_snapshot_impl(app)).await
}

fn get_runtime_snapshot_impl(app: AppHandle) -> Result<RuntimeSnapshot> {
    let directory = detect_directories(app.clone())?;
    let config = read_config(&app)?;
    let Some(selected) = directory.selected.clone() else {
        return Ok(RuntimeSnapshot {
            directory,
            process: inspect_cs2_process(None),
            files: None,
            drop_knives: None,
            isolation: None,
            installation: None,
        });
    };

    let root = csgo_path(&selected)?;
    let process = inspect_cs2_process(Some(&root));
    let running = process.running;
    let payload = payload_root().ok();
    let state = local_state_root(&app).ok();
    // A snapshot only reads the isolation state: healing an interrupted
    // transaction happens on Panel start and right before a launch.
    let isolation = state
        .as_deref()
        .and_then(|state| {
            let _ = installer::recover_incomplete(state, &root);
            launch_isolation::isolation_status(state, &root, launch_isolation::unix_now()).ok()
        });
    let installation = payload
        .as_deref()
        .zip(state.as_deref())
        .and_then(|(payload, state)| installer::inspect_quick(payload, state, &root).ok());

    Ok(RuntimeSnapshot {
        files: Some(validate_files_at(Some(&app), &root, false)?),
        drop_knives: Some(drop_knives_at(&root, &config, running)),
        isolation,
        directory,
        process,
        installation,
    })
}

async fn run_installation_task<T, F>(label: &'static str, task: F) -> Result<T>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T> + Send + 'static,
{
    tauri::async_runtime::spawn_blocking(task)
        .await
        .map_err(|error| {
            AppError::new("E1003", "internal", format!("{label} task failed: {error}"))
        })?
}

#[tauri::command]
async fn inspect_installation(app: AppHandle, csgo: String) -> Result<InstallationInspection> {
    run_installation_task("Installation inspection", move || {
        let root = csgo_path(&csgo)?;
        installer::recover_incomplete(&local_state_root(&app)?, &root)?;
        installer::inspect(&payload_root()?, &local_state_root(&app)?, &root)
    })
    .await
}

#[tauri::command]
async fn get_install_plan(app: AppHandle, csgo: String) -> Result<InstallPlan> {
    run_installation_task("Install preflight", move || {
        let root = csgo_path(&csgo)?;
        ensure_target_not_running(&root)?;
        installer::plan(&payload_root()?, &local_state_root(&app)?, &root)
    })
    .await
}

#[tauri::command]
async fn install_payload(app: AppHandle, csgo: String) -> Result<InstallTransactionResult> {
    run_installation_task("Payload installation", move || {
        let root = csgo_path(&csgo)?;
        let payload = payload_root()?;
        let state = local_state_root(&app)?;
        let report = collect_install_checks(&payload, &state, &root)?;
        ensure_install_checks_pass(&report)?;
        ensure_target_not_running(&root)?;
        ensure_steam_app_idle(&root)?;
        logging::append(&state, "INFO", "install.started", &root.to_string_lossy());
        let result = installer::install(&payload, &state, &root, false);
        match &result {
            Ok(value) => logging::append(
                &state,
                "INFO",
                "install.completed",
                &format!("{} files", value.installed_files),
            ),
            Err(error) => logging::append(&state, "ERROR", "install.failed", &error.detail),
        }
        result
    })
    .await
}

#[tauri::command]
async fn repair_payload(app: AppHandle, csgo: String) -> Result<InstallTransactionResult> {
    run_installation_task("Payload repair", move || {
        let root = csgo_path(&csgo)?;
        let payload = payload_root()?;
        let state = local_state_root(&app)?;
        let report = collect_install_checks(&payload, &state, &root)?;
        ensure_install_checks_pass(&report)?;
        ensure_target_not_running(&root)?;
        ensure_steam_app_idle(&root)?;
        logging::append(&state, "INFO", "repair.started", &root.to_string_lossy());
        let result = installer::install(&payload, &state, &root, true);
        match &result {
            Ok(value) => logging::append(
                &state,
                "INFO",
                "repair.completed",
                &format!("{} files", value.installed_files),
            ),
            Err(error) => logging::append(&state, "ERROR", "repair.failed", &error.detail),
        }
        result
    })
    .await
}

#[tauri::command]
async fn restore_payload(app: AppHandle, csgo: String) -> Result<RestoreResult> {
    run_installation_task("Payload restore", move || {
        restore_payload_impl(&app, &csgo, false)
    })
    .await
}

#[tauri::command]
async fn restore_pristine_cs2(app: AppHandle, csgo: String) -> Result<RestoreResult> {
    run_installation_task("Pristine CS2 restore", move || {
        restore_payload_impl(&app, &csgo, true)
    })
    .await
}

fn restore_payload_impl(app: &AppHandle, csgo: &str, pristine: bool) -> Result<RestoreResult> {
    let root = csgo_path(csgo)?;
    ensure_target_not_running(&root)?;
    ensure_steam_app_idle(&root)?;
    let state = local_state_root(app)?;
    // Asking for a restored CS2 also means asking for an unmodified launch
    // state, so the isolation file is converged here too; the payload never
    // owns gameinfo.gi, so this cannot race the transaction below.
    launch_isolation::restore_clean(&state, &root)?;
    let operation = if pristine {
        "restore_pristine"
    } else {
        "restore"
    };
    logging::append(
        &state,
        "INFO",
        &format!("{operation}.started"),
        &root.to_string_lossy(),
    );
    let result = if pristine {
        installer::restore_pristine(&payload_root()?, &state, &root)
    } else {
        installer::restore(&payload_root()?, &state, &root)
    };
    match &result {
        Ok(value) => logging::append(
            &state,
            "INFO",
            &format!("{operation}.completed"),
            &format!(
                "restored={}, removed={}, preserved={}",
                value.restored_files, value.removed_files, value.preserved_files
            ),
        ),
        Err(error) => logging::append(
            &state,
            "ERROR",
            &format!("{operation}.failed"),
            &error.detail,
        ),
    }
    result
}

#[tauri::command]
async fn export_diagnostics(
    app: AppHandle,
    csgo: Option<String>,
) -> Result<diagnostics::DiagnosticArchive> {
    run_installation_task("Diagnostic export", move || {
        export_diagnostics_impl(app, csgo)
    })
    .await
}

fn export_diagnostics_impl(
    app: AppHandle,
    csgo: Option<String>,
) -> Result<diagnostics::DiagnosticArchive> {
    let root = csgo.as_deref().map(csgo_path).transpose()?;
    let snapshot = get_runtime_snapshot_impl(app.clone())?;
    let state = local_state_root(&app)?;
    let source = root
        .as_deref()
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_else(|| "panel-only".to_string());
    logging::append(&state, "INFO", "diagnostics.started", &source);
    let snapshot = serde_json::to_value(snapshot)?;
    let result = diagnostics::export(&state, root.as_deref(), &snapshot);
    match &result {
        Ok(value) => logging::append(
            &state,
            "INFO",
            "diagnostics.completed",
            &format!("{} files: {}", value.files_collected, value.path),
        ),
        Err(error) => logging::append(&state, "ERROR", "diagnostics.failed", &error.detail),
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn test_root() -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("cs2bi-knife-config-{suffix}"))
    }

    fn test_preset(paint: i32) -> KnifePreset {
        KnifePreset {
            paint,
            seed: 0,
            wear: 0.01,
            name_tag: String::new(),
            stattrak_enabled: false,
            stattrak_count: 0,
            souvenir_enabled: false,
            stickers: vec![],
            charm: None,
        }
    }

    fn test_sticker(slot: u8, id: u32) -> StickerPreset {
        StickerPreset {
            slot,
            id,
            schema: slot as u32,
            wear: 0.0,
            scale: 1.0,
            rotation: 0.0,
            offset_x: 0.0,
            offset_y: 0.0,
            custom_position: false,
        }
    }

    #[test]
    fn csgo_path_accepts_install_root_game_directory_and_csgo_directory() {
        let root = test_root();
        let game = root.join("game");
        let csgo = game.join("csgo");
        fs::create_dir_all(csgo.join("cfg")).unwrap();
        fs::write(csgo.join("gameinfo.gi"), b"gameinfo").unwrap();

        let expected = normalize_windows_canonical(fs::canonicalize(&csgo).unwrap());
        assert_eq!(csgo_path(root.to_str().unwrap()).unwrap(), expected);
        assert_eq!(csgo_path(game.to_str().unwrap()).unwrap(), expected);
        assert_eq!(csgo_path(csgo.to_str().unwrap()).unwrap(), expected);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn knife_config_is_clamped_and_written_to_game_plugin_path() {
        let root = test_root();
        let mut config = KnifeCustomizerConfig::default();
        config.enabled = true;
        config.loadouts.ct.default_knife_defindex = 515;
        config.loadouts.ct.knife_presets.insert(
            "515".into(),
            KnifePreset {
                paint: 568,
                seed: 1200,
                wear: -0.25,
                name_tag: "12345678901234567890extra".into(),
                stattrak_enabled: true,
                stattrak_count: -7,
                souvenir_enabled: false,
                stickers: vec![],
                charm: None,
            },
        );

        save_knife_config(&root, &mut config).unwrap();

        let saved = read_knife_config(&root).unwrap();
        let preset = &saved.loadouts.ct.knife_presets["515"];
        assert_eq!(saved.schema_version, COSMETICS_SCHEMA_VERSION);
        assert_eq!(saved.loadouts.ct.default_knife_defindex, 515);
        assert_eq!(preset.seed, 1000);
        assert_eq!(preset.wear, 0.0);
        assert_eq!(preset.name_tag, "12345678901234567890");
        assert_eq!(preset.stattrak_count, 0);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn default_knife_requires_a_matching_preset() {
        let mut config = KnifeCustomizerConfig::default();
        config.loadouts.ct.default_knife_defindex = 515;
        let error = normalize_knife_config(&mut config).unwrap_err();
        assert_eq!(error.code, "E1002");
        assert!(error.detail.contains("no saved preset"));
    }

    #[test]
    fn legacy_knife_config_without_glove_remains_readable() {
        let json = r#"{
            "enabled": true,
            "apply_to_human_players": true,
            "apply_to_dropped_knives": true,
            "apply_on_pickup": true,
            "default_knife_defindex": 0,
            "presets": {}
        }"#;
        let mut config: KnifeCustomizerConfig = serde_json::from_str(json).unwrap();
        migrate_legacy_config(&mut config);
        assert!(
            !serde_json::to_string(&config)
                .unwrap()
                .contains("apply_to_dropped_knives")
        );
        assert_eq!(config.schema_version, COSMETICS_SCHEMA_VERSION);
        assert!(!config.loadouts.ct.glove.enabled);
        assert_eq!(config.loadouts.t.glove.defindex, DEFAULT_GLOVE_DEFINDEX);
        assert_eq!(config.loadouts.t.glove.paint, DEFAULT_GLOVE_PAINT);
        assert_eq!(config.music_kit_id, 0);
    }

    #[test]
    fn enabling_an_empty_legacy_glove_uses_the_default_preset() {
        let mut config = KnifeCustomizerConfig::default();
        config.loadouts.t.glove = GlovePreset {
            enabled: true,
            defindex: 0,
            paint: 0,
            seed: 0,
            wear: 0.0,
        };

        normalize_knife_config(&mut config).unwrap();

        assert!(config.loadouts.t.glove.enabled);
        assert_eq!(config.loadouts.t.glove.defindex, DEFAULT_GLOVE_DEFINDEX);
        assert_eq!(config.loadouts.t.glove.paint, DEFAULT_GLOVE_PAINT);
        assert_eq!(config.loadouts.t.glove.wear, DEFAULT_GLOVE_WEAR);
    }

    #[test]
    fn atomic_json_write_replaces_an_existing_file() {
        let root = test_root();
        let path = root.join("config.json");
        write_json_atomic(&path, &serde_json::json!({ "value": 1 })).unwrap();
        write_json_atomic(&path, &serde_json::json!({ "value": 2 })).unwrap();

        let saved: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(saved["value"], 2);
        assert!(!path.with_extension("json.tmp").exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cosmetics_import_rejects_an_unsupported_bundle_before_writing() {
        let root = test_root();
        fs::create_dir_all(&root).unwrap();
        let source = root.join("unsupported.json");
        fs::write(
            &source,
            serde_json::to_vec(&serde_json::json!({
                "schema_version": 99,
                "kind": COSMETICS_EXPORT_KIND,
                "exported_at_unix": 1,
                "config": KnifeCustomizerConfig::default(),
            }))
            .unwrap(),
        )
        .unwrap();

        let error = read_cosmetics_preset(&source).unwrap_err();

        assert_eq!(error.code, "E1002");
        assert!(error.detail.contains("Unsupported cosmetics preset schema"));
        assert!(!knife_config_path(&root).exists());
        assert!(!gun_config_path(&root).exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cosmetics_export_and_import_are_atomic_and_keep_a_pre_import_backup() {
        let root = test_root();
        let mut original = KnifeCustomizerConfig::default();
        original.enabled = false;
        save_knife_config(&root, &mut original).unwrap();
        let original_knife = fs::read(knife_config_path(&root)).unwrap();
        let original_guns = fs::read(gun_config_path(&root)).unwrap();

        let export = root.join("preset.json");
        fs::write(&export, b"stale").unwrap();
        let result = export_cosmetics_preset_at(&root, &export).unwrap();
        assert_eq!(result.path, export.to_string_lossy());
        assert_eq!(result.size_bytes, fs::metadata(&export).unwrap().len());
        let mut bundle: CosmeticsPresetBundle =
            serde_json::from_slice(&fs::read(&export).unwrap()).unwrap();
        bundle.config.enabled = true;
        fs::write(&export, serde_json::to_vec_pretty(&bundle).unwrap()).unwrap();

        let backup = import_cosmetics_preset_at(&root, &export, || Ok(()))
            .unwrap()
            .unwrap();

        assert!(read_knife_config(&root).unwrap().enabled);
        assert_eq!(
            fs::read(backup.join("player_knife_presets.json")).unwrap(),
            original_knife
        );
        assert_eq!(
            fs::read(backup.join("player_gun_presets.json")).unwrap(),
            original_guns
        );
        assert!(fs::read_dir(knife_config_path(&root).parent().unwrap())
            .unwrap()
            .flatten()
            .all(|entry| !entry.file_name().to_string_lossy().contains(".cs2bi-")));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cosmetics_import_rolls_back_when_post_write_mirroring_fails() {
        let root = test_root();
        let mut original = KnifeCustomizerConfig::default();
        original.enabled = false;
        save_knife_config(&root, &mut original).unwrap();
        let original_knife = fs::read(knife_config_path(&root)).unwrap();
        let original_guns = fs::read(gun_config_path(&root)).unwrap();

        let source = root.join("preset.json");
        let mut replacement = original;
        replacement.enabled = true;
        let bundle = CosmeticsPresetBundle {
            schema_version: COSMETICS_EXPORT_SCHEMA_VERSION,
            kind: COSMETICS_EXPORT_KIND.into(),
            exported_at_unix: 1,
            config: replacement,
        };
        fs::write(&source, serde_json::to_vec_pretty(&bundle).unwrap()).unwrap();

        let error = import_cosmetics_preset_at(&root, &source, || {
            Err(AppError::transaction("simulated mirror failure"))
        })
        .unwrap_err();

        assert!(error.detail.contains("simulated mirror failure"));
        assert_eq!(fs::read(knife_config_path(&root)).unwrap(), original_knife);
        assert_eq!(fs::read(gun_config_path(&root)).unwrap(), original_guns);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn legacy_config_migration_restarts_the_portable_first_run_wizard() {
        let mut legacy = AppConfig::default();
        legacy.language = Some("english".into());
        legacy.csgo_path = Some(r"F:\SteamLibrary\game\csgo".into());
        legacy.first_run_done = true;
        legacy.first_run_step = None;

        let migrated = prepare_legacy_config_for_portable_state(legacy);

        assert!(!migrated.first_run_done);
        assert_eq!(migrated.first_run_step.as_deref(), Some("language"));
        assert_eq!(migrated.language.as_deref(), Some("english"));
        assert_eq!(
            migrated.csgo_path.as_deref(),
            Some(r"F:\SteamLibrary\game\csgo")
        );
    }

    #[test]
    fn welcome_story_is_limited_to_the_1433_release_build() {
        assert!(welcome_story_release_eligible(true, "1.4.3.3"));
        assert!(!welcome_story_release_eligible(false, "1.4.3.3"));
        assert!(!welcome_story_release_eligible(true, "1.4.3.1"));
        assert!(!welcome_story_release_eligible(true, "1.4.3.2"));
    }

    #[test]
    fn panel_round_trip_preserves_gun_presets() {
        let root = test_root();
        let mut config = KnifeCustomizerConfig::default();
        config.music_kit_id = 36;
        config.loadouts.t.gun_presets.insert(
            "7".into(),
            KnifePreset {
                paint: 661,
                seed: 321,
                wear: 0.08,
                name_tag: String::new(),
                stattrak_enabled: false,
                stattrak_count: 12,
                souvenir_enabled: true,
                stickers: vec![],
                charm: None,
            },
        );

        save_knife_config(&root, &mut config).unwrap();
        let saved = read_knife_config(&root).unwrap();
        assert_eq!(saved.music_kit_id, 36);
        let ak = &saved.loadouts.t.gun_presets["7"];
        assert_eq!(ak.paint, 661);
        assert_eq!(ak.seed, 321);
        assert!(ak.souvenir_enabled);
        assert!(!ak.stattrak_enabled);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn v2_configs_migrate_with_empty_stickers_and_versioned_backups() {
        let root = test_root();
        let knife_path = knife_config_path(&root);
        let gun_path = gun_config_path(&root);
        fs::create_dir_all(knife_path.parent().unwrap()).unwrap();
        fs::write(&knife_path, r#"{
            "schema_version":2,"enabled":true,"apply_to_human_players":true,"apply_on_pickup":true,
            "music_kit_id":36,"loadouts":{"ct":{"default_knife_defindex":0,"knife_presets":{},"glove":{"enabled":false,"defindex":5030,"paint":10048,"seed":0,"wear":0.01},"gun_presets":{}},"t":{"default_knife_defindex":0,"knife_presets":{},"glove":{"enabled":false,"defindex":5030,"paint":10048,"seed":0,"wear":0.01},"gun_presets":{}}},
            "shared_weapon_links":{}
        }"#).unwrap();
        fs::write(&gun_path, r#"{
            "schema_version":2,"ct":{},"t":{"7":{"paint":661,"seed":123,"wear":0.08,"name_tag":"AK","stattrak_enabled":false,"stattrak_count":0,"souvenir_enabled":false}},"shared_weapon_links":{}
        }"#).unwrap();

        let config = read_knife_config(&root).unwrap();

        assert_eq!(config.schema_version, COSMETICS_SCHEMA_VERSION);
        assert!(!config.stickers_enabled);
        assert_eq!(config.music_kit_id, 36);
        assert_eq!(config.loadouts.t.gun_presets["7"].paint, 661);
        assert!(config.loadouts.t.gun_presets["7"].stickers.is_empty());
        assert!(versioned_backup_path(&knife_path, 2).is_file());
        assert!(versioned_backup_path(&gun_path, 2).is_file());
        assert!(fs::read_to_string(versioned_backup_path(&gun_path, 2)).unwrap().contains("\"schema_version\":2"));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn v3_stickers_gain_weapon_schema_without_losing_the_base_skin() {
        let root = test_root();
        let knife_path = knife_config_path(&root);
        let gun_path = gun_config_path(&root);
        fs::create_dir_all(knife_path.parent().unwrap()).unwrap();
        fs::write(&knife_path, r#"{
            "schema_version":3,"enabled":true,"apply_to_human_players":true,"apply_on_pickup":true,
            "music_kit_id":0,"stickers_enabled":true,"loadouts":{"ct":{"default_knife_defindex":0,"knife_presets":{},"glove":{"enabled":false,"defindex":5030,"paint":10048,"seed":0,"wear":0.01},"gun_presets":{}},"t":{"default_knife_defindex":0,"knife_presets":{},"glove":{"enabled":false,"defindex":5030,"paint":10048,"seed":0,"wear":0.01},"gun_presets":{}}},"shared_weapon_links":{}
        }"#).unwrap();
        fs::write(&gun_path, r#"{
            "schema_version":3,"ct":{},"t":{"7":{"paint":661,"seed":321,"wear":0.08,"name_tag":"AK","stattrak_enabled":false,"stattrak_count":0,"souvenir_enabled":false,"stickers":[{"slot":3,"id":1,"wear":0,"scale":1,"rotation":0,"offset_x":0,"offset_y":0,"custom_position":false}]}},"shared_weapon_links":{}
        }"#).unwrap();

        let config = read_knife_config(&root).unwrap();

        assert_eq!(config.schema_version, COSMETICS_SCHEMA_VERSION);
        assert!(config.stickers_enabled);
        assert!(!config.charms_enabled);
        assert_eq!(config.loadouts.t.gun_presets["7"].paint, 661);
        assert_eq!(config.loadouts.t.gun_presets["7"].stickers[0].schema, 3);
        assert!(versioned_backup_path(&gun_path, 3).is_file());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn malformed_sticker_fields_are_dropped_without_losing_base_skins() {
        let root = test_root();
        let knife_path = knife_config_path(&root);
        let gun_path = gun_config_path(&root);
        fs::create_dir_all(knife_path.parent().unwrap()).unwrap();
        fs::write(&knife_path, r#"{
            "schema_version":3,"enabled":true,"apply_to_human_players":true,"apply_on_pickup":true,"music_kit_id":0,"stickers_enabled":true,
            "loadouts":{"ct":{"default_knife_defindex":515,"knife_presets":{"515":{"paint":568,"seed":0,"wear":0.01,"name_tag":"","stattrak_enabled":false,"stattrak_count":0,"stickers":[{"slot":0,"id":1,"wear":0,"scale":1,"rotation":0,"offset_x":0,"offset_y":0,"custom_position":false}]}},"glove":{"enabled":false,"defindex":5030,"paint":10048,"seed":0,"wear":0.01},"gun_presets":{}},"t":{"default_knife_defindex":0,"knife_presets":{},"glove":{"enabled":false,"defindex":5030,"paint":10048,"seed":0,"wear":0.01},"gun_presets":{}}},"shared_weapon_links":{}
        }"#).unwrap();
        fs::write(&gun_path, r#"{
            "schema_version":3,"ct":{},"t":{"7":{"paint":661,"seed":321,"wear":0.08,"name_tag":"AK","stattrak_enabled":false,"stattrak_count":0,"souvenir_enabled":false,"stickers":[{"slot":0,"id":4294967295,"wear":0,"scale":1,"rotation":0,"offset_x":0,"offset_y":0,"custom_position":false}]}},"shared_weapon_links":{}
        }"#).unwrap();

        let config = read_knife_config(&root).unwrap();

        assert_eq!(config.loadouts.ct.knife_presets["515"].paint, 568);
        assert!(config.loadouts.ct.knife_presets["515"].stickers.is_empty());
        assert_eq!(config.loadouts.t.gun_presets["7"].paint, 661);
        assert_eq!(config.loadouts.t.gun_presets["7"].seed, 321);
        assert!(config.loadouts.t.gun_presets["7"].stickers.is_empty());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn sticker_validation_rejects_duplicates_unknown_ids_non_finite_values_and_knives() {
        let mut config = KnifeCustomizerConfig::default();
        let mut gun = test_preset(661);
        gun.stickers = vec![test_sticker(0, 1), test_sticker(0, 1)];
        config.loadouts.t.gun_presets.insert("7".into(), gun.clone());
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("unique"));

        gun.stickers = vec![test_sticker(0, u32::MAX)];
        config.loadouts.t.gun_presets.insert("7".into(), gun.clone());
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("Unknown"));

        gun.stickers = vec![StickerPreset { scale: f32::NAN, ..test_sticker(0, 1) }];
        config.loadouts.t.gun_presets.insert("7".into(), gun);
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("range"));

        let mut unsupported = test_preset(661);
        unsupported.stickers = vec![test_sticker(0, 1)];
        let mut config = KnifeCustomizerConfig::default();
        config.loadouts.ct.gun_presets.insert("42".into(), unsupported);
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("not supported"));

        let mut knife = test_preset(568);
        knife.stickers = vec![test_sticker(0, 1)];
        let mut config = KnifeCustomizerConfig::default();
        config.loadouts.ct.knife_presets.insert("515".into(), knife);
        config.loadouts.ct.default_knife_defindex = 515;
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("Knife stickers"));
    }

    #[test]
    fn charm_validation_uses_catalog_ids_and_weapon_owned_placements() {
        let charm_id = *valid_charm_ids().iter().next().unwrap();
        let placement_id = cosmetic_placements()[&7].charm_positions[0].placement_id;
        let mut gun = test_preset(661);
        gun.charm = Some(CharmPreset { id: charm_id, placement_id, seed: 42 });
        let mut config = KnifeCustomizerConfig::default();
        config.loadouts.t.gun_presets.insert("7".into(), gun.clone());
        normalize_knife_config(&mut config).unwrap();

        gun.charm = Some(CharmPreset { id: u32::MAX, placement_id, seed: 0 });
        config.loadouts.t.gun_presets.insert("7".into(), gun.clone());
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("Unknown charm"));

        gun.charm = Some(CharmPreset { id: charm_id, placement_id: u32::MAX, seed: 0 });
        config.loadouts.t.gun_presets.insert("7".into(), gun);
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("placement"));

        let mut knife = test_preset(568);
        knife.charm = Some(CharmPreset { id: charm_id, placement_id, seed: 0 });
        let mut config = KnifeCustomizerConfig::default();
        config.loadouts.ct.knife_presets.insert("515".into(), knife);
        config.loadouts.ct.default_knife_defindex = 515;
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("charms"));
    }

    #[test]
    fn agent_validation_is_team_owned_and_v4_migration_keeps_it_disabled() {
        let ct_model = valid_agent_models(WeaponSide::Ct).iter().next().unwrap().clone();
        let t_model = valid_agent_models(WeaponSide::T).iter().next().unwrap().clone();
        let mut config = KnifeCustomizerConfig::default();
        config.loadouts.ct.agent_model = ct_model.clone();
        config.loadouts.t.agent_model = t_model;
        config.agents_enabled = true;
        normalize_knife_config(&mut config).unwrap();

        config.loadouts.t.agent_model = ct_model;
        assert!(normalize_knife_config(&mut config).unwrap_err().detail.contains("agent model"));

        let mut migrated = KnifeCustomizerConfig::default();
        migrated.schema_version = 4;
        migrated.agents_enabled = true;
        migrate_legacy_config(&mut migrated);
        assert_eq!(migrated.schema_version, COSMETICS_SCHEMA_VERSION);
        assert!(!migrated.agents_enabled);
    }

    #[test]
    fn sticker_change_detection_ignores_base_skin_edits_but_tracks_gate_and_slots() {
        let mut current = KnifeCustomizerConfig::default();
        current.loadouts.t.gun_presets.insert("7".into(), test_preset(661));
        let mut edited = current.clone();
        edited.loadouts.t.gun_presets.get_mut("7").unwrap().paint = 302;
        assert!(!sticker_configuration_changed(&current, &edited));

        edited.stickers_enabled = true;
        assert!(sticker_configuration_changed(&current, &edited));
        edited.stickers_enabled = false;
        edited.loadouts.t.gun_presets.get_mut("7").unwrap().stickers = vec![test_sticker(0, 1)];
        assert!(sticker_configuration_changed(&current, &edited));

        let mut agent_edited = current.clone();
        agent_edited.loadouts.ct.agent_model = valid_agent_models(WeaponSide::Ct).iter().next().unwrap().clone();
        assert!(sticker_configuration_changed(&current, &agent_edited));
    }

    #[test]
    fn release_gate_preserves_enabled_decorations_and_saved_slots() {
        let mut app_config = AppConfig::default();
        app_config.experimental_stickers_enabled = true;
        apply_release_feature_gates(&mut app_config);
        assert!(app_config.experimental_stickers_enabled);

        let mut cosmetics = KnifeCustomizerConfig::default();
        cosmetics.stickers_enabled = true;
        cosmetics.charms_enabled = true;
        cosmetics.agents_enabled = true;
        let mut preset = test_preset(661);
        preset.stickers = vec![test_sticker(0, 1)];
        cosmetics.loadouts.t.gun_presets.insert("7".into(), preset);
        normalize_knife_config(&mut cosmetics).unwrap();

        assert!(cosmetics.stickers_enabled);
        assert!(cosmetics.charms_enabled);
        assert!(cosmetics.agents_enabled);
        assert_eq!(cosmetics.loadouts.t.gun_presets["7"].stickers.len(), 1);
    }

    #[test]
    fn schema_one_cosmetics_exports_remain_importable() {
        let root = test_root();
        fs::create_dir_all(&root).unwrap();
        let source = root.join("legacy-export.json");
        let mut config = KnifeCustomizerConfig::default();
        config.schema_version = 2;
        fs::write(&source, serde_json::to_vec_pretty(&CosmeticsPresetBundle {
            schema_version: LEGACY_COSMETICS_EXPORT_SCHEMA_VERSION,
            kind: COSMETICS_EXPORT_KIND.into(),
            exported_at_unix: 1,
            config,
        }).unwrap()).unwrap();

        let imported = read_cosmetics_preset(&source).unwrap();

        assert_eq!(imported.schema_version, COSMETICS_SCHEMA_VERSION);
        assert!(!imported.stickers_enabled);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn legacy_configs_migrate_by_weapon_side_and_are_backed_up_once() {
        let root = test_root();
        let knife_path = knife_config_path(&root);
        let gun_path = gun_config_path(&root);
        fs::create_dir_all(knife_path.parent().unwrap()).unwrap();
        fs::write(&knife_path, r#"{
            "enabled": true,
            "apply_to_human_players": true,
            "apply_on_pickup": true,
            "default_knife_defindex": 515,
            "presets": {"515":{"paint":568,"seed":0,"wear":0.01,"name_tag":"","stattrak_enabled":false,"stattrak_count":0}},
            "glove":{"enabled":false,"defindex":5030,"paint":10048,"seed":0,"wear":0.01}
        }"#).unwrap();
        fs::write(&gun_path, r#"{
            "7":{"paint":661,"seed":0,"wear":0.01,"name_tag":"","stattrak_enabled":false,"stattrak_count":0},
            "9":{"paint":344,"seed":0,"wear":0.01,"name_tag":"","stattrak_enabled":false,"stattrak_count":0},
            "16":{"paint":309,"seed":0,"wear":0.01,"name_tag":"","stattrak_enabled":false,"stattrak_count":0}
        }"#).unwrap();

        let mut config = read_knife_config(&root).unwrap();
        assert_eq!(config.loadouts.ct.default_knife_defindex, 515);
        assert_eq!(config.loadouts.t.default_knife_defindex, 515);
        assert!(config.loadouts.t.gun_presets.contains_key("7"));
        assert!(!config.loadouts.ct.gun_presets.contains_key("7"));
        assert!(config.loadouts.ct.gun_presets.contains_key("16"));
        assert!(!config.loadouts.t.gun_presets.contains_key("16"));
        assert_eq!(
            config.loadouts.ct.gun_presets["9"],
            config.loadouts.t.gun_presets["9"]
        );
        assert_eq!(config.shared_weapon_links["9"], true);
        assert!(legacy_backup_path(&knife_path).exists());
        assert!(legacy_backup_path(&gun_path).exists());
        let backup = fs::read(&legacy_backup_path(&knife_path)).unwrap();
        save_knife_config(&root, &mut config).unwrap();
        assert_eq!(fs::read(legacy_backup_path(&knife_path)).unwrap(), backup);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn linked_shared_weapon_base_presets_must_match_but_decorations_may_differ() {
        let mut config = KnifeCustomizerConfig::default();
        let mut left = KnifePreset {
            paint: 344,
            seed: 0,
            wear: 0.01,
            name_tag: String::new(),
            stattrak_enabled: false,
            stattrak_count: 0,
            souvenir_enabled: false,
            stickers: vec![],
            charm: None,
        };
        let mut right = left.clone();
        left.stickers = vec![test_sticker(0, 1)];
        right.stickers = vec![test_sticker(1, 2)];
        config
            .loadouts
            .ct
            .gun_presets
            .insert("9".into(), left.clone());
        config
            .loadouts
            .t
            .gun_presets
            .insert("9".into(), right.clone());
        normalize_knife_config(&mut config).unwrap();
        assert_eq!(config.loadouts.ct.gun_presets["9"].stickers[0].id, 1);
        assert_eq!(config.loadouts.t.gun_presets["9"].stickers[0].id, 2);

        right.paint = 279;
        config
            .loadouts
            .ct
            .gun_presets
            .insert("9".into(), left.clone());
        config.loadouts.t.gun_presets.insert("9".into(), right);
        let error = normalize_knife_config(&mut config).unwrap_err();
        assert!(error.detail.contains("base presets must match"));

        config.shared_weapon_links.insert("9".into(), false);
        normalize_knife_config(&mut config).unwrap();
        left.paint = config.loadouts.ct.gun_presets["9"].paint;
        assert_eq!(left.paint, 344);
    }
    fn isolation_fixture(label: &str) -> (PathBuf, PathBuf, PathBuf) {
        let base = std::env::temp_dir().join(format!(
            "cs2bi-launch-{label}-{}",
            std::process::id()
        ));
        let target = base.join("game/csgo");
        let state = base.join("state");
        fs::create_dir_all(
            target.join("addons/counterstrikesharp/plugins/PlayerKnifeCustomizer"),
        )
        .unwrap();
        fs::create_dir_all(&state).unwrap();
        fs::write(target.join("gameinfo.gi"), "SearchPaths\r\n{\r\n\tGame\tcsgo\r\n}\r\n").unwrap();
        (base, target, state)
    }

    #[test]
    fn local_launch_arguments_ask_steam_for_the_insecure_local_window() {
        let (base, target, state) = isolation_fixture("arguments");
        let prepared =
            launch_isolation::prepare_local_launch(&state, &target, launch_isolation::unix_now())
                .unwrap();

        assert_eq!(prepared.arguments, vec!["-applaunch", "730", "-insecure", "-console"]);
        assert_eq!(prepared.options, "-insecure -console");
        assert!(prepared.insecure);
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn a_failed_steam_spawn_restores_the_clean_gameinfo() {
        let (base, target, state) = isolation_fixture("spawn-failure");
        let prepared =
            launch_isolation::prepare_local_launch(&state, &target, launch_isolation::unix_now())
                .unwrap();
        assert!(fs::read_to_string(target.join("gameinfo.gi"))
            .unwrap()
            .contains("csgo/addons/metamod"));

        let error = spawn_local_launch(&prepared, &state, &target, |arguments| {
            assert_eq!(arguments, vec!["-applaunch", "730", "-insecure", "-console"]);
            Err(std::io::Error::other("steam refused to start"))
        })
        .unwrap_err();

        assert_eq!(error.category, "launch");
        assert_eq!(
            fs::read_to_string(target.join("gameinfo.gi")).unwrap(),
            "SearchPaths\r\n{\r\n\tGame\tcsgo\r\n}\r\n"
        );
        let status =
            launch_isolation::isolation_status(&state, &target, launch_isolation::unix_now())
                .unwrap();
        assert!(status.clean);
        assert!(status.pending.is_none());
        assert!(!status.ticket_live);
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn a_successful_spawn_leaves_the_isolation_window_open() {
        let (base, target, state) = isolation_fixture("spawn-ok");
        let prepared =
            launch_isolation::prepare_local_launch(&state, &target, launch_isolation::unix_now())
                .unwrap();

        let result = spawn_local_launch(&prepared, &state, &target, |_| Ok(())).unwrap();

        assert!(result.insecure);
        assert_eq!(result.options, "-insecure -console");
        let status =
            launch_isolation::isolation_status(&state, &target, launch_isolation::unix_now())
                .unwrap();
        assert!(!status.clean);
        assert!(status.ticket_live);
        fs::remove_dir_all(base).unwrap();
    }
}

/// Close a launch-isolation transaction an earlier Panel process left behind.
/// Only ever runs while CS2 is closed: a running game keeps its search path and
/// the plugin restores the clean file on shutdown.
fn recover_isolation_on_startup(app: &AppHandle) {
    let Ok(config) = read_config(app) else { return };
    let Some(selected) = config.csgo_path.as_deref() else { return };
    let Ok(root) = csgo_path(selected) else { return };
    if inspect_cs2_process(Some(&root)).running {
        return;
    }
    let Ok(state) = local_state_root(app) else { return };
    match launch_isolation::recover(&state, &root, false, launch_isolation::unix_now()) {
        Ok(true) => logging::append(
            &state,
            "INFO",
            "panel.isolation_recovered",
            &format!("target={}", root.display()),
        ),
        Ok(false) => {}
        Err(error) => logging::append(
            &state,
            "ERROR",
            "panel.isolation_recovery_failed",
            &format!("target={}, {}", root.display(), error.detail),
        ),
    }
}

pub fn run() {
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if let Ok(root) = app_storage::root() {
            logging::append(&root, "FATAL", "panel.panic", &info.to_string());
        }
        previous_hook(info);
    }));
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| { if let Some(w) = app.get_webview_window("main") { let _ = w.set_focus(); } }))
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            if let Ok(root) = app_storage::root() {
                let removed = logging::cleanup(&root).unwrap_or(0);
                let archives_removed = diagnostics::cleanup_archives(&root).unwrap_or(0);
                logging::append(&root, "INFO", "panel.started", &format!("version={}, logs_collected={removed}, archives_collected={archives_removed}", app_version::display()));
            }
            // Startup self-heal: an earlier Panel process may have died between
            // inserting the project search path and the game reporting in.
            recover_isolation_on_startup(app.handle());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_config, save_config, should_present_welcome_story,
            detect_directories, select_directory, validate_files,
            get_launch_isolation, launch_local_cosmetics,
            get_drop_knives, set_drop_knives, get_knife_customizer, save_knife_customizer,
            export_cosmetics_preset, import_cosmetics_preset,
            get_runtime_snapshot, get_cs2_process,
            inspect_installation, get_install_plan, install_payload, repair_payload,
            restore_payload, restore_pristine_cs2, export_diagnostics,
            get_panel_memory, save_panel_memory, record_panel_error, run_install_checks,
            appearance::get_appearance, appearance::save_appearance,
            appearance::export_appearance, appearance::import_appearance])
        .run(tauri::generate_context!())
        .expect("error while running the Local Arena panel");
}
