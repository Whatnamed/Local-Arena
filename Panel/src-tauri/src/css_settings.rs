//! Ownership of the single CounterStrikeSharp setting this runtime depends on.
//!
//! CounterStrikeSharp blocks writes to the economic item fields cosmetics need
//! (`m_iEntityQuality`, `m_flFallbackWear`, `m_iItemIDHigh`, `m_bInitialized` and
//! friends) whenever `FollowCS2ServerGuidelines` is enabled, so a local cosmetics
//! session cannot apply anything while that property holds `true`. `core.json`
//! itself belongs to CounterStrikeSharp and may carry unrelated user settings, so
//! this module reads and rewrites exactly that one property and records enough
//! state to put it back.

use crate::{AppError, Result, atomic_fs};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::fs;
use std::path::{Path, PathBuf};

pub const CORE_RELATIVE: &str = "addons/counterstrikesharp/configs/core.json";
pub const CORE_EXAMPLE_RELATIVE: &str = "addons/counterstrikesharp/configs/core.example.json";
pub const GUIDELINE_KEY: &str = "FollowCS2ServerGuidelines";
const OWNERSHIP_FILE: &str = "css-core-settings.json";
const OWNERSHIP_SCHEMA: u32 = 1;

/// What this product did to `core.json` before it started managing the property.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ownership {
    pub schema_version: u32,
    /// `core.json` did not exist and this product created it.
    pub created: bool,
    /// The value the property held beforehand, or `None` when the file existed
    /// without the key.
    pub original_value: Option<bool>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Reconciled {
    /// This product created `core.json` from the shipped example.
    pub created: bool,
    /// The property changed, so the file was rewritten.
    pub changed: bool,
}

pub fn core_path(target: &Path) -> PathBuf {
    target.join(CORE_RELATIVE)
}

fn read_document(path: &Path, label: &str) -> Result<Option<Map<String, Value>>> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(AppError::transaction(format!(
                "Cannot read {label} ({}): {error}",
                path.display()
            )));
        }
    };
    parse_document(&bytes, label).map(Some)
}

fn parse_document(bytes: &[u8], label: &str) -> Result<Map<String, Value>> {
    match serde_json::from_slice::<Value>(bytes) {
        Ok(Value::Object(document)) => Ok(document),
        Ok(_) => Err(AppError::transaction(format!(
            "{label} is not a JSON object, so its settings cannot be inspected safely"
        ))),
        Err(error) => Err(AppError::transaction(format!(
            "{label} could not be parsed ({error}); the file was left untouched"
        ))),
    }
}

fn guideline_value(document: &Map<String, Value>) -> Result<Option<bool>> {
    match document.get(GUIDELINE_KEY) {
        None => Ok(None),
        Some(Value::Bool(enabled)) => Ok(Some(*enabled)),
        Some(other) => Err(AppError::transaction(format!(
            "{GUIDELINE_KEY} must be a boolean, found {other}"
        ))),
    }
}

/// The property as it stands, or `None` when `core.json` does not exist yet.
pub fn read_guideline(target: &Path) -> Result<Option<bool>> {
    match read_document(&core_path(target), "CounterStrikeSharp core.json")? {
        None => Ok(None),
        Some(document) => guideline_value(&document),
    }
}

fn patched(document: &mut Map<String, Value>) -> Vec<u8> {
    document.insert(GUIDELINE_KEY.to_string(), Value::Bool(false));
    let mut text =
        serde_json::to_string_pretty(&Value::Object(document.clone())).unwrap_or_default();
    text.push('\n');
    text.into_bytes()
}

fn write_document(path: &Path, bytes: &[u8]) -> Result<()> {
    atomic_fs::write_replace(path, bytes).map_err(|error| {
        AppError::transaction(format!(
            "Cannot write {} ({error}); the previous file is still in place",
            path.display()
        ))
    })?;
    let verified = read_document(path, "CounterStrikeSharp core.json")?
        .ok_or_else(|| AppError::transaction("core.json disappeared after the reconciliation"))?;
    if guideline_value(&verified)? != Some(false) {
        return Err(AppError::transaction(format!(
            "{GUIDELINE_KEY} was not stored as false in {}",
            path.display()
        )));
    }
    Ok(())
}

/// Make the CounterStrikeSharp setting satisfy the cosmetics runtime requirement,
/// creating `core.json` from the shipped example when CounterStrikeSharp has not
/// written one yet.
pub fn reconcile(target: &Path) -> Result<Reconciled> {
    let path = core_path(target);
    let existing = read_document(&path, "CounterStrikeSharp core.json")?;
    if let Some(document) = &existing {
        if guideline_value(document)? == Some(false) {
            return Ok(Reconciled {
                created: false,
                changed: false,
            });
        }
    }
    let created = existing.is_none();
    let mut document = match existing {
        Some(document) => document,
        None => {
            let example = target.join(CORE_EXAMPLE_RELATIVE);
            read_document(&example, "CounterStrikeSharp core.example.json")?.ok_or_else(|| {
                AppError::transaction(format!(
                    "Neither core.json nor core.example.json exists in {}; install the CounterStrikeSharp payload first",
                    example.parent().map_or_else(|| String::from("(unknown)"), |parent| parent.display().to_string())
                ))
            })?
        }
    };
    let bytes = patched(&mut document);
    write_document(&path, &bytes)?;
    Ok(Reconciled {
        created,
        changed: true,
    })
}

/// Capture the pre-management state so a later restore can hand the setting back.
pub fn capture_ownership(target: &Path) -> Result<Ownership> {
    let path = core_path(target);
    match read_document(&path, "CounterStrikeSharp core.json")? {
        Some(document) => Ok(Ownership {
            schema_version: OWNERSHIP_SCHEMA,
            created: false,
            original_value: guideline_value(&document)?,
        }),
        None => Ok(Ownership {
            schema_version: OWNERSHIP_SCHEMA,
            created: true,
            original_value: None,
        }),
    }
}

fn ownership_path(installation_dir: &Path) -> PathBuf {
    installation_dir.join(OWNERSHIP_FILE)
}

pub fn write_ownership(installation_dir: &Path, ownership: &Ownership) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(ownership)
        .map_err(|error| AppError::transaction(error.to_string()))?;
    fs::create_dir_all(installation_dir).map_err(AppError::transaction_io)?;
    atomic_fs::write_replace(&ownership_path(installation_dir), &bytes)
        .map_err(AppError::transaction_io)
}

/// The recorded state, or `None` when this product never touched the setting.
pub fn read_ownership(installation_dir: &Path) -> Option<Ownership> {
    let path = ownership_path(installation_dir);
    if !path.is_file() {
        return None;
    }
    fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Ownership>(&bytes).ok())
        .filter(|ownership| ownership.schema_version == OWNERSHIP_SCHEMA)
}

pub fn clear_ownership(installation_dir: &Path) {
    let path = ownership_path(installation_dir);
    if path.is_file() {
        let _ = fs::remove_file(&path);
    }
}

/// Put the property back the way it was, or remove a `core.json` this product
/// created. Unknown settings are preserved, and a file the user replaced by hand
/// is only edited, never deleted.
pub fn revert(target: &Path, ownership: &Ownership) -> Result<()> {
    let path = core_path(target);
    let Some(mut document) = read_document(&path, "CounterStrikeSharp core.json")? else {
        return Ok(());
    };
    if ownership.created {
        fs::remove_file(&path).map_err(|error| {
            AppError::transaction(format!(
                "Cannot remove the generated core.json ({}): {error}",
                path.display()
            ))
        })?;
        return Ok(());
    }
    match ownership.original_value {
        Some(value) => {
            document.insert(GUIDELINE_KEY.to_string(), Value::Bool(value));
        }
        None => {
            document.remove(GUIDELINE_KEY);
        }
    }
    let mut text = serde_json::to_string_pretty(&Value::Object(document))
        .map_err(|error| AppError::transaction(error.to_string()))?;
    text.push('\n');
    atomic_fs::write_replace(&path, text.as_bytes()).map_err(|error| {
        AppError::transaction(format!(
            "Cannot restore core.json ({}): {error}",
            path.display()
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn root(name: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!(
            "cs2bi-css-settings-{name}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(base.join("addons/counterstrikesharp/configs")).unwrap();
        base
    }

    fn write(path: &Path, text: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }

    fn example(target: &Path) -> PathBuf {
        target.join(CORE_EXAMPLE_RELATIVE)
    }

    #[test]
    fn a_guideline_that_blocks_cosmetics_writes_is_flipped_without_losing_other_settings() {
        let target = root("existing-true");
        write(
            &core_path(&target),
            "{\n  \"ServerName\": \"mine\",\n  \"FollowCS2ServerGuidelines\": true,\n  \"FutureToggle\": { \"nested\": [1, 2] }\n}\n",
        );

        let reconciled = reconcile(&target).unwrap();
        assert_eq!(
            reconciled,
            Reconciled {
                created: false,
                changed: true
            }
        );
        assert_eq!(read_guideline(&target).unwrap(), Some(false));
        let stored: Value = serde_json::from_slice(&fs::read(core_path(&target)).unwrap()).unwrap();
        assert_eq!(stored["ServerName"], "mine");
        assert_eq!(stored["FutureToggle"]["nested"][1], 2);
        fs::remove_dir_all(target).unwrap();
    }

    #[test]
    fn an_already_satisfied_setting_is_not_rewritten() {
        let target = root("existing-false");
        write(&core_path(&target), "{\"FollowCS2ServerGuidelines\": false}\n");
        let before = fs::read(core_path(&target)).unwrap();

        let reconciled = reconcile(&target).unwrap();
        assert_eq!(
            reconciled,
            Reconciled {
                created: false,
                changed: false
            }
        );
        assert_eq!(fs::read(core_path(&target)).unwrap(), before);
        fs::remove_dir_all(target).unwrap();
    }

    #[test]
    fn a_missing_core_json_is_generated_from_the_shipped_example() {
        let target = root("missing-core");
        write(
            &example(&target),
            "{\"FollowCS2ServerGuidelines\": true, \"PluginAutoLoadEnabled\": true}\n",
        );

        let ownership = capture_ownership(&target).unwrap();
        assert!(ownership.created);
        assert_eq!(ownership.original_value, None);

        let reconciled = reconcile(&target).unwrap();
        assert_eq!(
            reconciled,
            Reconciled {
                created: true,
                changed: true
            }
        );
        assert_eq!(read_guideline(&target).unwrap(), Some(false));
        let stored: Value = serde_json::from_slice(&fs::read(core_path(&target)).unwrap()).unwrap();
        assert_eq!(stored["PluginAutoLoadEnabled"], true);
        fs::remove_dir_all(target).unwrap();
    }

    #[test]
    fn an_unparsable_core_json_is_reported_and_left_untouched() {
        let target = root("malformed");
        let bytes = b"{ this is not json";
        write_raw(&core_path(&target), bytes);

        let error = reconcile(&target).unwrap_err();
        assert!(error.detail.contains("could not be parsed"), "{error:?}");
        assert!(error.detail.contains("left untouched"), "{error:?}");
        assert_eq!(fs::read(core_path(&target)).unwrap(), bytes);
        fs::remove_dir_all(target).unwrap();
    }

    fn write_raw(path: &Path, bytes: &[u8]) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, bytes).unwrap();
    }

    #[test]
    fn a_non_boolean_setting_is_refused_rather_than_overwritten_blindly() {
        let target = root("wrong-type");
        write(&core_path(&target), "{\"FollowCS2ServerGuidelines\": \"yes\"}");

        let error = reconcile(&target).unwrap_err();
        assert!(error.detail.contains("must be a boolean"), "{error:?}");
        assert_eq!(
            fs::read_to_string(core_path(&target)).unwrap(),
            "{\"FollowCS2ServerGuidelines\": \"yes\"}"
        );
        fs::remove_dir_all(target).unwrap();
    }

    #[test]
    fn restoring_hands_the_property_back_and_removes_a_generated_file() {
        let kept = root("revert-value");
        write(&core_path(&kept), "{\"FollowCS2ServerGuidelines\": true}\n");
        let ownership = capture_ownership(&kept).unwrap();
        reconcile(&kept).unwrap();

        revert(&kept, &ownership).unwrap();
        assert_eq!(read_guideline(&kept).unwrap(), Some(true));
        assert!(core_path(&kept).is_file());
        fs::remove_dir_all(kept).unwrap();

        let generated = root("revert-created");
        write(
            &example(&generated),
            "{\"FollowCS2ServerGuidelines\": true}\n",
        );
        let generated_ownership = capture_ownership(&generated).unwrap();
        reconcile(&generated).unwrap();

        revert(&generated, &generated_ownership).unwrap();
        assert!(!core_path(&generated).exists());
        assert!(example(&generated).is_file());
        fs::remove_dir_all(generated).unwrap();
    }

    #[test]
    fn a_key_the_user_never_had_is_removed_rather_than_invented_on_restore() {
        let target = root("revert-absent");
        write(&core_path(&target), "{\"ServerName\": \"mine\"}\n");
        let ownership = capture_ownership(&target).unwrap();
        assert_eq!(ownership.original_value, None);

        reconcile(&target).unwrap();
        assert_eq!(read_guideline(&target).unwrap(), Some(false));

        revert(&target, &ownership).unwrap();
        let stored: Value = serde_json::from_slice(&fs::read(core_path(&target)).unwrap()).unwrap();
        assert_eq!(stored.get(GUIDELINE_KEY), None);
        assert_eq!(stored["ServerName"], "mine");
        fs::remove_dir_all(target).unwrap();
    }

    #[test]
    fn ownership_survives_the_install_directory_round_trip() {
        let directory = root("ownership-sidecar").join("installation");
        let ownership = Ownership {
            schema_version: OWNERSHIP_SCHEMA,
            created: true,
            original_value: Some(true),
        };
        assert_eq!(read_ownership(&directory), None);
        write_ownership(&directory, &ownership).unwrap();
        assert_eq!(read_ownership(&directory), Some(ownership));
        clear_ownership(&directory);
        assert_eq!(read_ownership(&directory), None);
    }

    #[test]
    fn a_reconciliation_leaves_no_temporary_file_behind() {
        let target = root("atomic");
        write(&core_path(&target), "{\"FollowCS2ServerGuidelines\": true}\n");
        reconcile(&target).unwrap();
        let leftovers = fs::read_dir(core_path(&target).parent().unwrap())
            .unwrap()
            .filter_map(|entry| entry.ok())
            .filter(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains(".tmp")
            })
            .count();
        assert_eq!(leftovers, 0);
        fs::remove_dir_all(target).unwrap();
    }
}
