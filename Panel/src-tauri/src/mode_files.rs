use crate::atomic_fs;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;

pub(crate) type ModeResult<T> = std::result::Result<T, String>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum LaunchMode {
    Online,
    Preview,
}

const LAUNCH_STATE_DIR: &str = "launch-isolation";
const LAUNCH_JOURNAL: &str = "transaction.json";
const OWNED_SEARCH_PATHS: [&str; 1] = ["csgo/addons/metamod"];

#[derive(Clone, Debug, Serialize, Deserialize)]
struct LaunchJournal {
    schema_version: u8,
    target: String,
    prepared_sha256: String,
}

impl LaunchMode {
    pub(crate) fn parse(value: Option<&str>) -> ModeResult<Self> {
        match value {
            Some("online") => Ok(Self::Online),
            Some("preview") => Ok(Self::Preview),
            // Legacy config values remain readable, but Cosmetics-only local
            // mode never enables an enhanced bot profile.
            Some("bots") => Ok(Self::Preview),
            _ => Err("Select a valid game mode before launching CS2".into()),
        }
    }

    pub(crate) fn insecure(self) -> bool {
        self != Self::Online
    }
}

pub(crate) fn contains_metamod_search_path(bytes: &[u8]) -> bool {
    String::from_utf8_lossy(bytes)
        .to_ascii_lowercase()
        .contains("csgo/addons/metamod")
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

fn rewrite_gameinfo(bytes: &[u8], include_local_runtime: bool) -> ModeResult<Vec<u8>> {
    let text = std::str::from_utf8(bytes)
        .map_err(|error| format!("gameinfo.gi is not valid UTF-8: {error}"))?;
    let newline = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let trailing_newline = text.ends_with('\n');
    let mut output = Vec::new();
    let mut inserted = false;

    for line in text.lines() {
        if game_path_value(line).is_some_and(|value| {
            OWNED_SEARCH_PATHS
                .iter()
                .any(|owned| value.eq_ignore_ascii_case(owned))
        }) {
            continue;
        }
        if include_local_runtime
            && !inserted
            && game_path_value(line).is_some_and(|value| value.eq_ignore_ascii_case("csgo"))
        {
            let indent: String = line.chars().take_while(|ch| ch.is_whitespace()).collect();
            output.push(format!("{indent}Game\tcsgo/addons/metamod"));
            inserted = true;
        }
        output.push(line.to_string());
    }

    if include_local_runtime && !inserted {
        return Err("gameinfo.gi has no primary 'Game csgo' SearchPath".into());
    }

    let mut rewritten = output.join(newline);
    if trailing_newline {
        rewritten.push_str(newline);
    }
    Ok(rewritten.into_bytes())
}

fn launch_state_directory(state_root: &Path, target: &Path) -> std::path::PathBuf {
    let normalized = target
        .to_string_lossy()
        .replace('/', "\\")
        .to_ascii_lowercase();
    let digest = Sha256::digest(normalized.as_bytes());
    state_root
        .join(LAUNCH_STATE_DIR)
        .join(format!("{:x}", digest)[..16].to_string())
}

fn launch_journal_path(state_root: &Path, target: &Path) -> std::path::PathBuf {
    launch_state_directory(state_root, target).join(LAUNCH_JOURNAL)
}

fn target_matches(journal: &LaunchJournal, target: &Path) -> bool {
    journal.target == target.to_string_lossy()
}

fn read_journal(state_root: &Path, target: &Path) -> ModeResult<Option<LaunchJournal>> {
    let path = launch_journal_path(state_root, target);
    if !path.is_file() {
        return Ok(None);
    }
    let journal: LaunchJournal =
        serde_json::from_slice(&fs::read(&path).map_err(|error| error.to_string())?)
            .map_err(|error| format!("Invalid launch isolation journal: {error}"))?;
    if journal.schema_version != 1 || !target_matches(&journal, target) {
        return Err("Launch isolation journal belongs to another CS2 installation".into());
    }
    Ok(Some(journal))
}

fn remove_journal(state_root: &Path, target: &Path) -> ModeResult<()> {
    let path = launch_journal_path(state_root, target);
    let state_directory = path.parent().map(Path::to_path_buf);
    if path.is_file() {
        fs::remove_file(&path).map_err(|error| error.to_string())?;
    }
    if let Some(parent) = state_directory.as_deref() {
        let _ = fs::remove_dir(parent);
        if let Some(root) = parent.parent() {
            let _ = fs::remove_dir(root);
        }
    }
    Ok(())
}

fn sha256_bytes(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn restore_clean_contents(root: &Path) -> ModeResult<bool> {
    let destination = root.join("gameinfo.gi");
    if !destination.is_file() {
        return Err(format!(
            "Current CS2 gameinfo.gi is missing: {}",
            destination.display()
        ));
    }
    let active = fs::read(&destination).map_err(|error| error.to_string())?;
    let clean = rewrite_gameinfo(&active, false)?;
    let changed = active != clean;
    if changed {
        atomic_fs::write_replace(&destination, &clean).map_err(|error| error.to_string())?;
        if fs::read(&destination).map_err(|error| error.to_string())? != clean {
            return Err(format!(
                "Clean gameinfo.gi verification failed after writing {}",
                destination.display()
            ));
        }
    }
    Ok(changed)
}

pub(crate) fn recover_launch_transaction(state_root: &Path, root: &Path) -> ModeResult<bool> {
    let Some(journal) = read_journal(state_root, root)? else {
        return Ok(false);
    };
    let _ = journal;
    restore_clean_contents(root)?;
    remove_journal(state_root, root)?;
    Ok(true)
}

pub(crate) fn restore_clean_launch(state_root: &Path, root: &Path) -> ModeResult<()> {
    restore_clean_contents(root)?;
    remove_journal(state_root, root)
}

pub(crate) fn prepare_local_launch(
    state_root: &Path,
    root: &Path,
    mode: LaunchMode,
) -> ModeResult<()> {
    if mode == LaunchMode::Online {
        return restore_clean_launch(state_root, root);
    }
    let _ = recover_launch_transaction(state_root, root)?;
    let destination = root.join("gameinfo.gi");
    if !destination.is_file() {
        return Err(format!(
            "Current CS2 gameinfo.gi is missing: {}",
            destination.display()
        ));
    }
    let active = fs::read(&destination).map_err(|error| error.to_string())?;
    let clean = rewrite_gameinfo(&active, false)?;
    let local = rewrite_gameinfo(&clean, true)?;
    let journal_path = launch_journal_path(state_root, root);
    if let Some(parent) = journal_path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let journal = LaunchJournal {
        schema_version: 1,
        target: root.to_string_lossy().into_owned(),
        prepared_sha256: sha256_bytes(&local),
    };
    let journal_bytes = serde_json::to_vec_pretty(&journal)
        .map_err(|error| format!("Cannot serialize launch isolation journal: {error}"))?;
    atomic_fs::write_replace(&journal_path, &journal_bytes).map_err(|error| error.to_string())?;
    if let Err(error) = atomic_fs::write_replace(&destination, &local) {
        return Err(error.to_string());
    }
    let installed = fs::read(&destination).map_err(|error| error.to_string())?;
    if installed != local {
        return Err(format!(
            "Local gameinfo.gi verification failed after writing {}",
            destination.display()
        ));
    }
    if !contains_metamod_search_path(&installed) {
        return Err("Local CS2 launch was not prepared with MetaMod SearchPath".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn test_root() -> PathBuf {
        std::env::temp_dir().join(format!(
            "cs2bi-plus-mode-files-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }

    #[test]
    fn local_launch_journal_roundtrips_without_losing_unknown_search_paths() {
        let base = test_root();
        let root = base.join("game/csgo");
        let state = base.join("panel-state");
        fs::create_dir_all(&root).unwrap();
        fs::write(
            root.join("gameinfo.gi"),
            b"SearchPaths\n{\n\tGame\tcsgo/addons/foreign\n\tGame\tcsgo\n}\nSteamSetting\tbefore\n",
        )
        .unwrap();

        prepare_local_launch(&state, &root, LaunchMode::Preview).unwrap();
        let local = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert_eq!(local.matches("csgo/addons/metamod").count(), 1);
        assert!(local.contains("csgo/addons/foreign"));
        assert!(launch_journal_path(&state, &root).is_file());

        restore_clean_launch(&state, &root).unwrap();
        let clean = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert!(!clean.contains("csgo/addons/metamod"));
        assert!(clean.contains("csgo/addons/foreign"));
        assert!(clean.contains("SteamSetting\tbefore"));
        assert!(!launch_journal_path(&state, &root).exists());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn repeated_local_prepare_is_idempotent_and_recovery_converges_after_steam_update() {
        let base = test_root();
        let root = base.join("game/csgo");
        let state = base.join("panel-state");
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("gameinfo.gi"), b"SearchPaths\n{\nGame csgo\n}\n").unwrap();

        prepare_local_launch(&state, &root, LaunchMode::Preview).unwrap();
        prepare_local_launch(&state, &root, LaunchMode::Preview).unwrap();
        let repeated = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert_eq!(repeated.matches("csgo/addons/metamod").count(), 1);

        fs::write(
            root.join("gameinfo.gi"),
            b"SearchPaths\n{\nGame csgo/addons/metamod\nGame csgo\nGame csgo/steam-update\n}\nNewDepotSetting\t2\n",
        )
        .unwrap();
        assert!(recover_launch_transaction(&state, &root).unwrap());
        let recovered = fs::read_to_string(root.join("gameinfo.gi")).unwrap();
        assert!(!recovered.contains("csgo/addons/metamod"));
        assert!(recovered.contains("csgo/steam-update"));
        assert!(recovered.contains("NewDepotSetting\t2"));
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn malformed_or_missing_gameinfo_fails_closed_without_removing_journal() {
        let base = test_root();
        let root = base.join("game/csgo");
        let state = base.join("panel-state");
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("gameinfo.gi"), b"SearchPaths\n{\nGame csgo\n}\n").unwrap();
        prepare_local_launch(&state, &root, LaunchMode::Preview).unwrap();
        fs::write(root.join("gameinfo.gi"), [0xff, 0xfe]).unwrap();

        assert!(recover_launch_transaction(&state, &root).is_err());
        assert!(launch_journal_path(&state, &root).is_file());

        fs::remove_file(root.join("gameinfo.gi")).unwrap();
        assert!(restore_clean_launch(&state, &root).is_err());
        assert!(launch_journal_path(&state, &root).is_file());
        fs::remove_dir_all(base).unwrap();
    }
}
