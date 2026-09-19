//! Transactional launch isolation.
//!
//! The durable state of `gameinfo.gi` is always the clean one. The project search
//! path exists only inside the window between an explicit Panel launch of local
//! cosmetics mode and the runtime going away again, so a CS2 started straight from
//! Steam never loads this Mod. Independent restore paths converge on the same
//! clean file: the Panel (journal recovery on next start, observed game exit) and
//! the in-game plugin (shutdown, plus self-heal when it loads without a live
//! launch ticket).
//!
//! Every write is line-scoped and re-derived from the file currently on disk, so a
//! Steam update that rewrites `gameinfo.gi` is never clobbered by a stale copy and
//! search paths this project did not insert are preserved.

use crate::{AppError, Result, atomic_fs};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// Search paths this project owns and may insert or remove.
pub(crate) const OWNED_SEARCH_PATHS: &[&str] = &["csgo/addons/metamod"];

/// Handshake file shared with the in-game plugin. It sits in the plugin payload
/// directory because that is the one location both processes can resolve without
/// the game being told the Panel's state root.
pub(crate) const MARKER_RELATIVE: &str =
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/panel_isolation.json";

/// A Panel launch is only credible for as long as CS2 could plausibly still be
/// starting up. The plugin refuses to treat an older ticket as authorization.
pub(crate) const TICKET_TTL_SECONDS: i64 = 300;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct LaunchTicket {
    pub(crate) nonce: String,
    pub(crate) expires_at_unix: i64,
}

impl LaunchTicket {
    pub(crate) fn is_live(&self, now_unix: i64) -> bool {
        self.expires_at_unix > now_unix
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct IsolationMarker {
    pub(crate) schema_version: u8,
    pub(crate) gameinfo: String,
    pub(crate) search_paths: Vec<String>,
    #[serde(default)]
    pub(crate) ticket: Option<LaunchTicket>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum PendingPhase {
    Prepared,
    Inserted,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct IsolationJournal {
    schema_version: u8,
    target: String,
    phase: PendingPhase,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct IsolationStatus {
    pub(crate) gameinfo_present: bool,
    pub(crate) clean: bool,
    pub(crate) project_paths_present: Vec<String>,
    pub(crate) pending: Option<PendingPhase>,
    pub(crate) ticket_live: bool,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct PreparedLaunch {
    pub(crate) arguments: Vec<&'static str>,
    pub(crate) options: String,
    pub(crate) insecure: bool,
    pub(crate) nonce: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum LaunchKind {
    /// A CS2 the user starts from Steam carries no arguments at all. The Panel
    /// never writes launch options, so this arm exists to keep the rule that
    /// `-insecure` is local-mode-only expressible and testable in one place.
    #[allow(dead_code)]
    Plain,
    LocalCosmetics,
}

pub(crate) fn steam_arguments(kind: LaunchKind) -> Vec<&'static str> {
    match kind {
        LaunchKind::Plain => vec![],
        LaunchKind::LocalCosmetics => vec!["-applaunch", "730", "-insecure", "-console"],
    }
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

fn join_lines(lines: &[String], newline: &str, trailing_newline: bool) -> Vec<u8> {
    let mut bytes = lines.join(newline).into_bytes();
    if trailing_newline {
        bytes.extend_from_slice(newline.as_bytes());
    }
    bytes
}

fn split_lines(bytes: &[u8]) -> std::result::Result<(Vec<&str>, &str, bool), String> {
    let text = std::str::from_utf8(bytes)
        .map_err(|error| format!("gameinfo.gi is not valid UTF-8: {error}"))?;
    Ok((text.lines().collect(), if text.contains("\r\n") { "\r\n" } else { "\n" }, text.ends_with('\n')))
}

/// Remove only the entries this project owns. Anything else in the file, including
/// unknown search paths left by other tools, is reproduced verbatim.
pub(crate) fn strip_paths(bytes: &[u8], entries: &[&str]) -> std::result::Result<Vec<u8>, String> {
    let (lines, newline, trailing) = split_lines(bytes)?;
    let kept: Vec<String> = lines
        .into_iter()
        .filter(|line| {
            !game_path_value(line).is_some_and(|value| {
                entries.iter().any(|entry| value.eq_ignore_ascii_case(entry))
            })
        })
        .map(str::to_string)
        .collect();
    Ok(join_lines(&kept, newline, trailing))
}

/// Insert the owned entries ahead of the primary `Game csgo` path. Idempotent: a
/// file that already carries them is normalised, never duplicated.
pub(crate) fn insert_paths(bytes: &[u8], entries: &[&str]) -> std::result::Result<Vec<u8>, String> {
    let stripped = strip_paths(bytes, entries)?;
    let (lines, newline, trailing) = split_lines(&stripped)?;
    let mut output: Vec<String> = Vec::with_capacity(lines.len() + entries.len());
    let mut inserted = false;

    for line in lines {
        if !inserted && game_path_value(line).is_some_and(|value| value.eq_ignore_ascii_case("csgo"))
        {
            let indent: String = line.chars().take_while(|ch| ch.is_whitespace()).collect();
            output.extend(entries.iter().map(|entry| format!("{indent}Game\t{entry}")));
            inserted = true;
        }
        output.push(line.to_string());
    }

    if !inserted {
        return Err("gameinfo.gi has no primary 'Game csgo' SearchPath".into());
    }
    Ok(join_lines(&output, newline, trailing))
}

/// Canonical spelling of the owned entries that are currently present.
pub(crate) fn present_paths(bytes: &[u8], entries: &[&str]) -> Vec<String> {
    let Ok(text) = std::str::from_utf8(bytes) else {
        return vec![];
    };
    let mut present: Vec<String> = text
        .lines()
        .filter_map(game_path_value)
        .filter_map(|value| entries.iter().find(|entry| value.eq_ignore_ascii_case(entry)))
        .map(|entry| (*entry).to_string())
        .collect();
    present.sort();
    present.dedup();
    present
}

pub(crate) fn gameinfo_path(target: &Path) -> PathBuf {
    target.join("gameinfo.gi")
}

fn read_gameinfo(target: &Path) -> Result<Vec<u8>> {
    let path = gameinfo_path(target);
    fs::read(&path)
        .map_err(|error| AppError::launch(format!("Cannot read {}: {error}", path.display())))
}

fn write_verified(target: &Path, expected: &[u8]) -> Result<()> {
    let path = gameinfo_path(target);
    atomic_fs::write_replace(&path, expected).map_err(AppError::transaction_io)?;
    if fs::read(&path).map_err(AppError::transaction_io)? != *expected {
        return Err(AppError::launch(format!(
            "Launch isolation verification failed after writing {}",
            path.display()
        )));
    }
    Ok(())
}

fn installation_id(target: &Path) -> String {
    let normalized = target.to_string_lossy().replace('/', "\\").to_ascii_lowercase();
    format!("{:x}", Sha256::digest(normalized.as_bytes()))
}

fn journal_path(state_root: &Path, target: &Path) -> PathBuf {
    state_root.join("launch-isolation").join(installation_id(target)).join("journal.json")
}

fn write_journal(state_root: &Path, target: &Path, phase: PendingPhase) -> Result<()> {
    let path = journal_path(state_root, target);
    if let Some(directory) = path.parent() {
        fs::create_dir_all(directory).map_err(AppError::transaction_io)?;
    }
    let bytes = serde_json::to_vec_pretty(&IsolationJournal {
        schema_version: 1,
        target: target.to_string_lossy().into_owned(),
        phase,
    })
    .map_err(|error| AppError::transaction(error.to_string()))?;
    atomic_fs::write_replace(&path, &bytes).map_err(AppError::transaction_io)
}

fn read_journal(state_root: &Path, target: &Path) -> Result<Option<IsolationJournal>> {
    let path = journal_path(state_root, target);
    match fs::read(&path) {
        Ok(bytes) => {
            let journal: IsolationJournal = serde_json::from_slice(&bytes)
                .map_err(|error| AppError::transaction(format!("Invalid launch journal: {error}")))?;
            if journal.target != target.to_string_lossy() {
                return Err(AppError::transaction(
                    "Launch journal belongs to another CS2 installation",
                ));
            }
            Ok(Some(journal))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(AppError::transaction_io(error)),
    }
}

fn marker_path(target: &Path) -> PathBuf {
    target.join(MARKER_RELATIVE)
}

/// The marker is the only thing that tells the plugin which file and which lines
/// are ours, so it is never created opportunistically: the payload directory has
/// to be there already, and a restore only clears the ticket it owns.
fn write_marker(target: &Path, ticket: Option<LaunchTicket>) -> Result<Option<()>> {
    let path = marker_path(target);
    let Some(parent) = path.parent() else {
        return Err(AppError::launch("Cannot resolve the PlayerCosmetics plugin directory"));
    };
    if !parent.is_dir() {
        if ticket.is_none() {
            return Ok(None);
        }
        return Err(AppError::launch(
            "PlayerCosmetics is not installed; install the payload before launching local mode",
        ));
    }
    let marker = IsolationMarker {
        schema_version: 1,
        gameinfo: gameinfo_path(target).to_string_lossy().into_owned(),
        search_paths: OWNED_SEARCH_PATHS.iter().map(|entry| (*entry).to_string()).collect(),
        ticket,
    };
    let bytes = serde_json::to_vec_pretty(&marker)
        .map_err(|error| AppError::transaction(error.to_string()))?;
    atomic_fs::write_replace(&path, &bytes).map_err(AppError::transaction_io)?;
    Ok(Some(()))
}

pub(crate) fn live_ticket(target: &Path, now_unix: i64) -> Option<LaunchTicket> {
    let text = fs::read_to_string(marker_path(target)).ok()?;
    serde_json::from_str::<IsolationMarker>(&text)
        .ok()
        .and_then(|marker| marker.ticket)
        .filter(|ticket| ticket.is_live(now_unix))
}

fn clear_ticket(target: &Path) {
    if marker_path(target).is_file() {
        let _ = write_marker(target, None);
    }
}

/// Restore the durable clean state. A file that already carries no project path is
/// not rewritten, so this is safe to call from every recovery entry point.
pub(crate) fn restore_clean(state_root: &Path, target: &Path) -> Result<bool> {
    let current = read_gameinfo(target)?;
    let clean = strip_paths(&current, OWNED_SEARCH_PATHS).map_err(AppError::launch)?;
    let changed = clean != current;
    if changed {
        write_verified(target, &clean)?;
    }
    clear_ticket(target);
    let path = journal_path(state_root, target);
    if path.is_file() {
        fs::remove_file(path).map_err(AppError::transaction_io)?;
    }
    Ok(changed)
}

/// Finish or abandon the transaction a previous Panel process left behind. A
/// running game keeps its search path, because the engine already read the file
/// and the plugin restores it on shutdown.
pub(crate) fn recover(
    state_root: &Path,
    target: &Path,
    game_running: bool,
    now_unix: i64,
) -> Result<bool> {
    if read_journal(state_root, target)?.is_none() || game_running {
        return Ok(false);
    }
    let _ = live_ticket(target, now_unix);
    restore_clean(state_root, target).map(|_| true)
}

/// Insert the project search path and arm the launch ticket. The caller must spawn
/// CS2 next and restore clean on any failure.
pub(crate) fn prepare_local_launch(
    state_root: &Path,
    target: &Path,
    now_unix: i64,
) -> Result<PreparedLaunch> {
    let current = read_gameinfo(target)?;
    // Fail closed before touching anything: a malformed or unrecognised
    // gameinfo.gi is not ours to edit.
    let inserted = insert_paths(&current, OWNED_SEARCH_PATHS).map_err(AppError::launch)?;
    write_journal(state_root, target, PendingPhase::Prepared)?;
    let nonce = format!("{:x}{:x}", now_unix, now_unix ^ std::process::id() as i64);
    write_marker(
        target,
        Some(LaunchTicket { nonce: nonce.clone(), expires_at_unix: now_unix + TICKET_TTL_SECONDS }),
    )?;
    if inserted != current {
        write_verified(target, &inserted)?;
    }
    write_journal(state_root, target, PendingPhase::Inserted)?;
    if present_paths(&inserted, OWNED_SEARCH_PATHS).is_empty() {
        return Err(AppError::launch(
            "Launch isolation failed: gameinfo.gi does not load the managed runtime",
        ));
    }
    Ok(PreparedLaunch {
        arguments: steam_arguments(LaunchKind::LocalCosmetics),
        options: "-insecure -console".into(),
        insecure: true,
        nonce,
    })
}

pub(crate) fn isolation_status(
    state_root: &Path,
    target: &Path,
    now_unix: i64,
) -> Result<IsolationStatus> {
    let path = gameinfo_path(target);
    let bytes = match fs::read(&path) {
        Ok(bytes) => Some(bytes),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => return Err(AppError::io(error.to_string())),
    };
    let present = bytes
        .as_deref()
        .map(|bytes| present_paths(bytes, OWNED_SEARCH_PATHS))
        .unwrap_or_default();
    Ok(IsolationStatus {
        gameinfo_present: bytes.is_some(),
        clean: bytes.as_ref().is_some_and(|_| present.is_empty()),
        project_paths_present: present,
        pending: read_journal(state_root, target)?.map(|journal| journal.phase),
        ticket_live: live_ticket(target, now_unix).is_some(),
    })
}

pub(crate) fn unix_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    const CLEAN: &str = "SearchPaths\r\n{\r\n\tGame\tcsgo\r\n}\r\nNewDepotSetting\t1\r\n";
    const FOREIGN: &str =
        "SearchPaths\r\n{\r\n\tGame+Local\tWORKSHOP\r\n\tGame\tcsgo/addons/somethingelse\r\n\tGame\tcsgo\r\n}\r\n";

    fn fixture(label: &str) -> (PathBuf, PathBuf, PathBuf) {
        let base = std::env::temp_dir().join(format!(
            "la-isolation-{}-{}-{}",
            label,
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
        ));
        let target = base.join("game/csgo");
        let state = base.join("state");
        fs::create_dir_all(&target).unwrap();
        fs::create_dir_all(marker_path(&target).parent().unwrap()).unwrap();
        fs::create_dir_all(&state).unwrap();
        (base, target, state)
    }

    fn put(target: &Path, text: &str) {
        fs::write(gameinfo_path(target), text).unwrap();
    }

    fn read(target: &Path) -> String {
        fs::read_to_string(gameinfo_path(target)).unwrap()
    }

    #[test]
    fn clean_then_prepare_then_restore() {
        let (base, target, state) = fixture("roundtrip");
        put(&target, CLEAN);

        let prepared = prepare_local_launch(&state, &target, 1_000).unwrap();
        assert_eq!(prepared.arguments, vec!["-applaunch", "730", "-insecure", "-console"]);
        assert!(prepared.insecure);
        assert!(read(&target).contains("csgo/addons/metamod"));
        assert!(read(&target).contains("NewDepotSetting"));

        assert!(restore_clean(&state, &target).unwrap());
        assert_eq!(read(&target), CLEAN);
        assert!(!journal_path(&state, &target).exists());
        // Without a live ticket the plugin will never rewrite this file again.
        assert!(live_ticket(&target, 1_000).is_none());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn plain_launch_never_carries_insecure() {
        assert!(steam_arguments(LaunchKind::Plain).is_empty());
        assert!(steam_arguments(LaunchKind::LocalCosmetics)
            .iter()
            .any(|argument| *argument == "-insecure"));
    }

    #[test]
    fn prepare_is_idempotent_and_refreshes_the_ticket() {
        let (base, target, state) = fixture("idempotent");
        put(&target, CLEAN);

        prepare_local_launch(&state, &target, 1_000).unwrap();
        let first = read(&target);
        prepare_local_launch(&state, &target, 2_000).unwrap();

        assert_eq!(first, read(&target));
        assert_eq!(read(&target).matches("csgo/addons/metamod").count(), 1);
        // The refreshed ticket is live only until its own expiry: the observation
        // time has to be measured against it, not against a fixed offset.
        let expires_at = 2_000 + TICKET_TTL_SECONDS;
        assert_eq!(live_ticket(&target, expires_at - 1).unwrap().expires_at_unix, expires_at);
        assert!(live_ticket(&target, expires_at).is_none());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn interrupted_insert_is_recovered_without_losing_content() {
        let (base, target, state) = fixture("journal");
        put(&target, CLEAN);
        prepare_local_launch(&state, &target, 1_000).unwrap();
        // The Panel died after the write and the game never reported in.
        fs::remove_file(marker_path(&target)).unwrap();

        assert_eq!(
            isolation_status(&state, &target, 1_100).unwrap().pending,
            Some(PendingPhase::Inserted)
        );
        assert!(recover(&state, &target, false, 1_100).unwrap());
        assert_eq!(read(&target), CLEAN);
        assert!(isolation_status(&state, &target, 1_100).unwrap().pending.is_none());
        assert!(!recover(&state, &target, false, 1_100).unwrap());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn recovery_defers_to_a_running_game() {
        let (base, target, state) = fixture("running");
        put(&target, CLEAN);
        prepare_local_launch(&state, &target, 1_000).unwrap();

        assert!(!recover(&state, &target, true, 1_100).unwrap());
        assert!(read(&target).contains("csgo/addons/metamod"));
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn steam_updated_file_is_reinserted_not_overwritten() {
        let (base, target, state) = fixture("steam-update");
        put(&target, CLEAN);
        prepare_local_launch(&state, &target, 1_000).unwrap();
        restore_clean(&state, &target).unwrap();

        let updated =
            "SearchPaths\r\n{\r\n\tGame\tcsgo\r\n}\r\nNewDepotSetting\t2\r\nNewLine\t\"x\"\r\n";
        put(&target, updated);
        prepare_local_launch(&state, &target, 3_000).unwrap();
        let dirty = read(&target);
        assert!(dirty.contains("NewDepotSetting\t2"));
        assert!(dirty.contains("NewLine"));
        assert_eq!(dirty.matches("csgo/addons/metamod").count(), 1);

        restore_clean(&state, &target).unwrap();
        assert_eq!(read(&target), updated);
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn unknown_search_paths_survive_the_whole_cycle() {
        let (base, target, state) = fixture("foreign");
        put(&target, FOREIGN);
        prepare_local_launch(&state, &target, 1_000).unwrap();
        let dirty = read(&target);
        assert!(dirty.contains("Game+Local\tWORKSHOP"));
        assert!(dirty.contains("csgo/addons/somethingelse"));
        restore_clean(&state, &target).unwrap();
        assert_eq!(read(&target), FOREIGN);
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn malformed_missing_and_unowned_gameinfo_fail_closed() {
        let (base, target, state) = fixture("fail-closed");
        fs::remove_dir_all(marker_path(&target).parent().unwrap()).unwrap();

        // No gameinfo.gi at all.
        let error = prepare_local_launch(&state, &target, 1_000).unwrap_err();
        assert_eq!(error.code, "E1501");
        assert!(!journal_path(&state, &target).exists());

        // Present but without a primary `Game csgo` line.
        fs::create_dir_all(marker_path(&target).parent().unwrap()).unwrap();
        put(&target, "SearchPaths\n{\n\tGame core\n\tGame csgo_imported\n}\n");
        let error = prepare_local_launch(&state, &target, 1_000).unwrap_err();
        assert!(error.detail.contains("no primary 'Game csgo'"));
        assert!(!marker_path(&target).exists());
        assert_eq!(read(&target), "SearchPaths\n{\n\tGame core\n\tGame csgo_imported\n}\n");

        // Non-UTF-8 content.
        fs::write(gameinfo_path(&target), [0xff_u8, 0xfe, 0x00, 0x01]).unwrap();
        assert!(prepare_local_launch(&state, &target, 1_000).is_err());
        assert_eq!(fs::read(gameinfo_path(&target)).unwrap(), vec![0xff, 0xfe, 0x00, 0x01]);
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn prepare_refuses_when_the_payload_is_not_installed() {
        let (base, target, state) = fixture("no-payload");
        put(&target, CLEAN);
        fs::remove_dir_all(marker_path(&target).parent().unwrap()).unwrap();

        let error = prepare_local_launch(&state, &target, 1_000).unwrap_err();
        assert!(error.detail.contains("not installed"));
        // The journal was opened first, so the next start still heals the file.
        assert_eq!(read(&target), CLEAN);
        assert!(recover(&state, &target, false, 1_100).unwrap());
        assert_eq!(read(&target), CLEAN);
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn lf_and_missing_trailing_newline_are_preserved() {
        let (base, target, state) = fixture("line-endings");
        let lf = "SearchPaths\n{\n  Game csgo\n}";
        put(&target, lf);
        prepare_local_launch(&state, &target, 1_000).unwrap();
        let dirty = fs::read(gameinfo_path(&target)).unwrap();
        assert!(!dirty.contains(&b'\r'));
        assert!(dirty.starts_with(b"SearchPaths\n{\n"));
        restore_clean(&state, &target).unwrap();
        assert_eq!(fs::read(gameinfo_path(&target)).unwrap(), lf.as_bytes());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn marker_publishes_the_paths_the_plugin_may_rewrite() {
        let (base, target, state) = fixture("marker");
        put(&target, CLEAN);
        let prepared = prepare_local_launch(&state, &target, 1_000).unwrap();

        let marker: IsolationMarker =
            serde_json::from_str(&fs::read_to_string(marker_path(&target)).unwrap()).unwrap();
        assert_eq!(marker.gameinfo, gameinfo_path(&target).to_string_lossy());
        assert_eq!(marker.search_paths, vec!["csgo/addons/metamod".to_string()]);
        assert_eq!(marker.ticket.as_ref().unwrap().nonce, prepared.nonce);
        assert!(marker.ticket.unwrap().is_live(1_299));

        restore_clean(&state, &target).unwrap();
        let marker: IsolationMarker =
            serde_json::from_str(&fs::read_to_string(marker_path(&target)).unwrap()).unwrap();
        assert!(marker.ticket.is_none());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn status_reports_a_clean_installation_as_the_default() {
        let (base, target, state) = fixture("status");
        put(&target, CLEAN);
        let status = isolation_status(&state, &target, 1_000).unwrap();
        assert!(status.gameinfo_present);
        assert!(status.clean);
        assert!(status.project_paths_present.is_empty());
        assert!(!status.ticket_live);

        prepare_local_launch(&state, &target, 1_000).unwrap();
        let status = isolation_status(&state, &target, 1_000).unwrap();
        assert!(!status.clean);
        assert_eq!(status.project_paths_present, vec!["csgo/addons/metamod".to_string()]);
        assert!(status.ticket_live);
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn missing_gameinfo_is_reported_not_panicked() {
        let (base, target, state) = fixture("absent");
        let status = isolation_status(&state, &target, 1_000).unwrap();
        assert!(!status.gameinfo_present);
        assert!(!status.clean);
        fs::remove_dir_all(base).unwrap();
    }
}
