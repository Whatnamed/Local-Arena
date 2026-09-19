use crate::atomic_fs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) type ModeResult<T> = std::result::Result<T, String>;

const JOURNAL_FILE: &str = "launch_isolation_journal.json";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum LaunchMode {
    Online,
    Preview,
    Bots,
}

impl LaunchMode {
    pub(crate) fn parse(value: Option<&str>) -> ModeResult<Self> {
        match value {
            Some("online") => Ok(Self::Online),
            Some("preview") => Ok(Self::Preview),
            Some("bots") => Ok(Self::Bots),
            _ => Err("Select a valid game mode before launching CS2".into()),
        }
    }

    pub(crate) fn insecure(self) -> bool {
        self != Self::Online
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum JournalState {
    PreparedLocal,
    Clean,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct LaunchJournal {
    pub schema_version: u8,
    pub target: String,
    pub state: JournalState,
    pub timestamp: u64,
}

pub(crate) fn contains_metamod_search_path(bytes: &[u8]) -> bool {
    String::from_utf8_lossy(bytes)
        .to_ascii_lowercase()
        .contains("csgo/addons/metamod")
}

pub(crate) fn contains_botprofile_search_path(bytes: &[u8]) -> bool {
    String::from_utf8_lossy(bytes)
        .to_ascii_lowercase()
        .contains("csgo/overrides/botprofile.vpk")
}

fn game_path_value(line: &str) -> Option<&str> {
    let content = line.split_once("//").map_or(line, |(content, _)| content);
    let mut fields = content.split_whitespace();
    if !fields.next()?.eq_ignore_ascii_case("game") {
        return None;
    }
    let value = fields.next()?;
    if fields.next().is_some() {
        return None;
    }
    Some(value)
}

pub(crate) fn rewrite_gameinfo_clean(bytes: &[u8]) -> ModeResult<Vec<u8>> {
    let text = std::str::from_utf8(bytes)
        .map_err(|error| format!("gameinfo.gi is not valid UTF-8: {error}"))?;
    let newline = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let trailing_newline = text.ends_with('\n');
    let mut output = Vec::new();

    for line in text.lines() {
        if game_path_value(line).is_some_and(|value| {
            value.eq_ignore_ascii_case("csgo/addons/metamod")
                || value.eq_ignore_ascii_case("csgo/overrides/botprofile.vpk")
        }) {
            continue;
        }
        output.push(line.to_string());
    }

    let mut rewritten = output.join(newline);
    if trailing_newline {
        rewritten.push_str(newline);
    }
    Ok(rewritten.into_bytes())
}

pub(crate) fn rewrite_gameinfo_local(bytes: &[u8]) -> ModeResult<Vec<u8>> {
    let text = std::str::from_utf8(bytes)
        .map_err(|error| format!("gameinfo.gi is not valid UTF-8: {error}"))?;
    let newline = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let trailing_newline = text.ends_with('\n');
    let mut output = Vec::new();
    let mut inserted = false;

    for line in text.lines() {
        if game_path_value(line).is_some_and(|value| {
            value.eq_ignore_ascii_case("csgo/addons/metamod")
                || value.eq_ignore_ascii_case("csgo/overrides/botprofile.vpk")
        }) {
            continue;
        }
        if !inserted && game_path_value(line).is_some_and(|value| value.eq_ignore_ascii_case("csgo")) {
            let indent: String = line.chars().take_while(|ch| ch.is_whitespace()).collect();
            output.push(format!("{indent}Game\tcsgo/addons/metamod"));
            inserted = true;
        }
        output.push(line.to_string());
    }

    if !inserted {
        return Err("gameinfo.gi has no primary 'Game csgo' SearchPath".into());
    }

    let mut rewritten = output.join(newline);
    if trailing_newline {
        rewritten.push_str(newline);
    }
    Ok(rewritten.into_bytes())
}

fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn journal_path(state_dir: &Path) -> PathBuf {
    state_dir.join(JOURNAL_FILE)
}

fn write_journal(state_dir: &Path, target: &Path, state: JournalState) -> ModeResult<()> {
    fs::create_dir_all(state_dir).map_err(|e| e.to_string())?;
    let journal = LaunchJournal {
        schema_version: 1,
        target: target.to_string_lossy().to_string(),
        state,
        timestamp: current_timestamp(),
    };
    let bytes = serde_json::to_vec_pretty(&journal).map_err(|e| e.to_string())?;
    atomic_fs::write_replace(&journal_path(state_dir), &bytes).map_err(|e| e.to_string())
}

pub(crate) fn prepare_local_launch(root: &Path, state_dir: Option<&Path>) -> ModeResult<()> {
    let destination = root.join("gameinfo.gi");
    if !destination.is_file() {
        return Err(format!(
            "Current CS2 gameinfo.gi is missing: {}",
            destination.display()
        ));
    }

    let active = fs::read(&destination).map_err(|error| error.to_string())?;
    let local = rewrite_gameinfo_local(&active)?;

    if let Some(state) = state_dir {
        write_journal(state, root, JournalState::PreparedLocal)?;
    }

    atomic_fs::write_replace(&destination, &local).map_err(|error| error.to_string())?;
    let verified = fs::read(&destination).map_err(|error| error.to_string())?;
    if !contains_metamod_search_path(&verified) {
        return Err(format!(
            "Local launch preparation failed: metamod search path was not written to {}",
            destination.display()
        ));
    }
    if contains_botprofile_search_path(&verified) {
        return Err(
            "Local launch preparation failed: botprofile must not be mounted in cosmetics-only mode"
                .into(),
        );
    }

    cleanup_legacy_mode_backups(root)?;
    Ok(())
}

pub(crate) fn restore_clean_launch(root: &Path, state_dir: Option<&Path>) -> ModeResult<()> {
    let destination = root.join("gameinfo.gi");
    if !destination.is_file() {
        return Err(format!(
            "Current CS2 gameinfo.gi is missing: {}",
            destination.display()
        ));
    }

    let active = fs::read(&destination).map_err(|error| error.to_string())?;
    let clean = rewrite_gameinfo_clean(&active)?;

    atomic_fs::write_replace(&destination, &clean).map_err(|error| error.to_string())?;
    let verified = fs::read(&destination).map_err(|error| error.to_string())?;
    if contains_metamod_search_path(&verified) {
        return Err(format!(
            "Clean launch restoration failed: metamod search path still present in {}",
            destination.display()
        ));
    }
    if contains_botprofile_search_path(&verified) {
        return Err(format!(
            "Clean launch restoration failed: botprofile search path still present in {}",
            destination.display()
        ));
    }

    if let Some(state) = state_dir {
        let jpath = journal_path(state);
        if jpath.is_file() {
            let _ = fs::remove_file(jpath);
        }
    }

    cleanup_legacy_mode_backups(root)?;
    Ok(())
}

pub(crate) fn recover_launch_state(root: &Path, state_dir: Option<&Path>) -> ModeResult<bool> {
    let destination = root.join("gameinfo.gi");
    if !destination.is_file() {
        return Ok(false);
    }

    let has_journal = state_dir
        .map(|s| journal_path(s).is_file())
        .unwrap_or(false);

    let active = fs::read(&destination).map_err(|error| error.to_string())?;
    let has_metamod = contains_metamod_search_path(&active);
    let has_botprofile = contains_botprofile_search_path(&active);

    if has_journal || has_metamod || has_botprofile {
        restore_clean_launch(root, state_dir)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub(crate) fn build_launch_arguments(mode: LaunchMode) -> (Vec<&'static str>, String) {
    if mode.insecure() {
        (
            vec!["-applaunch", "730", "-insecure", "-console"],
            "-insecure -console".into(),
        )
    } else {
        (vec!["-applaunch", "730"], String::new())
    }
}

pub(crate) fn apply_launch_mode(root: &Path, mode: LaunchMode) -> ModeResult<()> {
    if mode == LaunchMode::Online {
        restore_clean_launch(root, None)
    } else {
        prepare_local_launch(root, None)
    }
}

fn cleanup_legacy_mode_backups(root: &Path) -> ModeResult<()> {
    let backup_root = root.join("backup");
    for relative in ["Online/gameinfo.gi", "WithBots/gameinfo.gi"] {
        let path = backup_root.join(relative);
        if path.is_file() {
            fs::remove_file(&path).map_err(|error| {
                format!("Cannot remove legacy PLUS mode file {}: {error}", path.display())
            })?;
        }
        if let Some(parent) = path.parent() {
            let _ = fs::remove_dir(parent);
        }
    }
    let _ = fs::remove_dir(backup_root);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn test_root(suffix: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "cs2-cosmetics-isolation-{}-{}-{}",
            std::process::id(),
            suffix,
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn clean_prepare_local_restore_clean_lifecycle() {
        let root = test_root("lifecycle");
        let state_dir = root.join("state");
        let clean_original = b"SearchPaths\r\n{\r\n\tGame\tcsgo\r\n}\r\nDepotVersion\t123\r\n";
        fs::write(root.join("gameinfo.gi"), clean_original).unwrap();

        // 1. Prepare local
        prepare_local_launch(&root, Some(&state_dir)).unwrap();
        let prepared = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert!(prepared.contains("csgo/addons/metamod"));
        assert!(!prepared.contains("csgo/overrides/botprofile.vpk"));
        assert!(prepared.contains("DepotVersion\t123"));
        assert!(journal_path(&state_dir).is_file());

        // 2. Restore clean
        restore_clean_launch(&root, Some(&state_dir)).unwrap();
        let cleaned = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert!(!cleaned.contains("csgo/addons/metamod"));
        assert!(!cleaned.contains("csgo/overrides/botprofile.vpk"));
        assert!(cleaned.contains("DepotVersion\t123"));
        assert!(!journal_path(&state_dir).is_file());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn prepare_local_is_idempotent() {
        let root = test_root("idempotent");
        let state_dir = root.join("state");
        let clean = b"SearchPaths\n{\n\tGame csgo\n}\n";
        fs::write(root.join("gameinfo.gi"), clean).unwrap();

        prepare_local_launch(&root, Some(&state_dir)).unwrap();
        let first = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        prepare_local_launch(&root, Some(&state_dir)).unwrap();
        let second = fs::read_to_string(root.join("gameinfo.gi")).unwrap();

        assert_eq!(first, second);
        let occurrences = second.matches("csgo/addons/metamod").count();
        assert_eq!(occurrences, 1, "Metamod must only be inserted once");

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn interrupted_journal_is_recovered_to_clean() {
        let root = test_root("recovery");
        let state_dir = root.join("state");
        let clean = b"SearchPaths\n{\n\tGame csgo\n}\n";
        fs::write(root.join("gameinfo.gi"), clean).unwrap();

        prepare_local_launch(&root, Some(&state_dir)).unwrap();
        assert!(journal_path(&state_dir).is_file());
        assert!(contains_metamod_search_path(&fs::read(root.join("gameinfo.gi")).unwrap()));

        // Simulate application restart after unexpected termination
        let recovered = recover_launch_state(&root, Some(&state_dir)).unwrap();
        assert!(recovered, "Uncommitted local state must be recovered");

        let active = fs::read(root.join("gameinfo.gi")).unwrap();
        assert!(!contains_metamod_search_path(&active));
        assert!(!journal_path(&state_dir).is_file());

        // Second recovery is a no-op
        let recovered_again = recover_launch_state(&root, Some(&state_dir)).unwrap();
        assert!(!recovered_again);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn steam_update_to_gameinfo_is_preserved_when_reprocessed() {
        let root = test_root("steam_update");
        let state_dir = root.join("state");
        let v1 = b"SearchPaths\n{\n\tGame csgo\n}\nBuildID 1000\n";
        fs::write(root.join("gameinfo.gi"), v1).unwrap();

        prepare_local_launch(&root, Some(&state_dir)).unwrap();

        // Simulate Steam downloading an update while clean or modded
        let updated_by_steam = b"SearchPaths\n{\n\tGame csgo/addons/metamod\n\tGame csgo\n}\nBuildID 1001\nNewEngineFeature 1\n";
        fs::write(root.join("gameinfo.gi"), updated_by_steam).unwrap();

        restore_clean_launch(&root, Some(&state_dir)).unwrap();
        let cleaned = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert!(!cleaned.contains("csgo/addons/metamod"));
        assert!(cleaned.contains("BuildID 1001"));
        assert!(cleaned.contains("NewEngineFeature 1"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn unknown_searchpaths_are_strictly_preserved() {
        let root = test_root("unknown_paths");
        let state_dir = root.join("state");
        let custom = b"SearchPaths\n{\n\tGame custom_maps\n\tGame workshop\n\tGame csgo\n\tGame core\n}\n";
        fs::write(root.join("gameinfo.gi"), custom).unwrap();

        prepare_local_launch(&root, Some(&state_dir)).unwrap();
        let prepared = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert!(prepared.contains("Game custom_maps"));
        assert!(prepared.contains("Game workshop"));
        assert!(prepared.contains("Game core"));
        assert!(prepared.contains("Game\tcsgo/addons/metamod"));

        restore_clean_launch(&root, Some(&state_dir)).unwrap();
        let restored = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert!(restored.contains("Game custom_maps"));
        assert!(restored.contains("Game workshop"));
        assert!(restored.contains("Game core"));
        assert!(!restored.contains("csgo/addons/metamod"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn malformed_or_missing_gameinfo_fails_closed() {
        let root = test_root("fail_closed");
        let state_dir = root.join("state");

        // Missing
        let err = prepare_local_launch(&root, Some(&state_dir)).unwrap_err();
        assert!(err.contains("missing"));

        // Malformed (no Game csgo)
        fs::write(root.join("gameinfo.gi"), b"SearchPaths\n{\n\tGame other\n}\n").unwrap();
        let err2 = prepare_local_launch(&root, Some(&state_dir)).unwrap_err();
        assert!(err2.contains("no primary 'Game csgo'"));

        // Invalid UTF-8
        fs::write(root.join("gameinfo.gi"), [0xFF, 0xFE, 0xFD]).unwrap();
        let err3 = prepare_local_launch(&root, Some(&state_dir)).unwrap_err();
        assert!(err3.contains("not valid UTF-8"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn launch_argument_builder_only_adds_insecure_for_local_mode() {
        let (online_args, online_opt) = build_launch_arguments(LaunchMode::Online);
        assert_eq!(online_args, vec!["-applaunch", "730"]);
        assert!(!online_args.contains(&"-insecure"));
        assert_eq!(online_opt, "");

        let (preview_args, preview_opt) = build_launch_arguments(LaunchMode::Preview);
        assert!(preview_args.contains(&"-insecure"));
        assert!(preview_args.contains(&"-console"));
        assert_eq!(preview_opt, "-insecure -console");

        let (bot_args, bot_opt) = build_launch_arguments(LaunchMode::Bots);
        assert!(bot_args.contains(&"-insecure"));
        assert_eq!(bot_opt, "-insecure -console");
    }
}
