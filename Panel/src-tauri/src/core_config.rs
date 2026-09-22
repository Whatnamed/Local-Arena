use crate::{AppError, Result, atomic_fs};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

pub const CORE_CONFIG_RELATIVE: &str = "addons/counterstrikesharp/configs/core.json";
pub const CORE_EXAMPLE_RELATIVE: &str = "addons/counterstrikesharp/configs/core.example.json";
pub const GUIDELINES_FIELD: &str = "FollowCS2ServerGuidelines";

const OWNERSHIP_SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct OwnershipRecord {
    schema_version: u32,
    target: String,
    #[serde(default)]
    original_document: Option<Value>,
    #[serde(default)]
    original_guidelines: Option<Value>,
}

fn target_key(target: &Path) -> String {
    let digest = Sha256::digest(target.to_string_lossy().as_bytes());
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn ownership_path(state_root: &Path, target: &Path) -> PathBuf {
    state_root
        .join("core-config")
        .join(format!("{}.json", target_key(target)))
}

fn core_path(target: &Path) -> PathBuf {
    target.join(CORE_CONFIG_RELATIVE.replace('/', "\\"))
}

fn core_example_path(target: &Path) -> PathBuf {
    target.join(CORE_EXAMPLE_RELATIVE.replace('/', "\\"))
}

fn write_json(path: &Path, value: &Value) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(value).map_err(|error| {
        AppError::transaction(format!("Cannot serialize CounterStrikeSharp core.json: {error}"))
    })?;
    atomic_fs::write_replace(path, &bytes).map_err(AppError::transaction_io)
}

fn read_json(path: &Path, context: &'static str) -> Result<Value> {
    let bytes = fs::read(path).map_err(|error| {
        AppError::launch(format!("Cannot read {context} ({}): {error}", path.display()))
    })?;
    serde_json::from_slice(&bytes).map_err(|error| {
        AppError::launch(format!("{context} is not valid JSON ({}): {error}", path.display()))
    })
}

fn write_record(path: &Path, record: &OwnershipRecord) -> Result<()> {
    let value = serde_json::to_value(record).map_err(|error| {
        AppError::transaction(format!("Cannot serialize core.json ownership state: {error}"))
    })?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(AppError::transaction_io)?;
    }
    write_json(path, &value)
}

fn read_record(path: &Path) -> Result<Option<OwnershipRecord>> {
    if !path.is_file() {
        return Ok(None);
    }
    let value = read_json(path, "core.json ownership state")?;
    let record: OwnershipRecord = serde_json::from_value(value).map_err(|error| {
        AppError::transaction(format!("Invalid core.json ownership state ({}): {error}", path.display()))
    })?;
    if record.schema_version != OWNERSHIP_SCHEMA_VERSION {
        return Err(AppError::transaction(format!(
            "Unsupported core.json ownership state version {}",
            record.schema_version
        )));
    }
    Ok(Some(record))
}

fn ensure_record_target(record: &OwnershipRecord, target: &Path) -> Result<()> {
    if !record.target.eq_ignore_ascii_case(&target.to_string_lossy()) {
        return Err(AppError::transaction(
            "core.json ownership state belongs to a different CS2 installation",
        ));
    }
    Ok(())
}

fn record_for_document(target: &Path, document: &Value) -> Result<OwnershipRecord> {
    let object = document.as_object().ok_or_else(|| {
        AppError::launch(format!(
            "CounterStrikeSharp core.json must contain a JSON object ({}).",
            core_path(target).display()
        ))
    })?;
    Ok(OwnershipRecord {
        schema_version: OWNERSHIP_SCHEMA_VERSION,
        target: target.to_string_lossy().into_owned(),
        original_document: Some(document.clone()),
        original_guidelines: object.get(GUIDELINES_FIELD).cloned(),
    })
}

fn record_for_missing_document(target: &Path) -> OwnershipRecord {
    OwnershipRecord {
        schema_version: OWNERSHIP_SCHEMA_VERSION,
        target: target.to_string_lossy().into_owned(),
        original_document: None,
        original_guidelines: None,
    }
}

fn current_source(target: &Path) -> Result<(PathBuf, Value)> {
    let config = core_path(target);
    if config.is_file() {
        return Ok((config.clone(), read_json(&config, "CounterStrikeSharp core.json")?));
    }
    let example = core_example_path(target);
    if example.is_file() {
        return Ok((example.clone(), read_json(&example, "CounterStrikeSharp core.example.json")?));
    }
    Err(AppError::launch(format!(
        "CounterStrikeSharp core.json is missing and no core.example.json is available ({}). Repair the Local Arena installation before starting a local mode.",
        config.display()
    )))
}

/// Capture the state before an installer or repair operation can replace the package config.
pub fn capture_before_install(state_root: &Path, target: &Path) -> Result<bool> {
    let path = ownership_path(state_root, target);
    if let Some(record) = read_record(&path)? {
        ensure_record_target(&record, target)?;
        return Ok(false);
    }

    let config = core_path(target);
    let record = if config.is_file() {
        record_for_document(target, &read_json(&config, "CounterStrikeSharp core.json")?)?
    } else {
        record_for_missing_document(target)
    };
    write_record(&path, &record)?;
    Ok(true)
}

pub fn discard_capture(state_root: &Path, target: &Path) -> Result<()> {
    let path = ownership_path(state_root, target);
    if path.is_file() {
        fs::remove_file(path).map_err(AppError::transaction_io)?;
    }
    Ok(())
}

/// Validate the current config or example without changing it. Install and repair use this
/// before mutating the target so malformed input fails closed.
pub fn validate_source(target: &Path) -> Result<()> {
    let (_, document) = current_source(target)?;
    if !document.is_object() {
        return Err(AppError::launch(
            "CounterStrikeSharp core.json must contain a JSON object before local mode can start.",
        ));
    }
    Ok(())
}

/// Before first install, neither file may exist yet because the package can provide it.
/// If either source is already present, validate it before the installer mutates the target.
pub fn validate_before_install(target: &Path) -> Result<()> {
    if !core_path(target).is_file() && !core_example_path(target).is_file() {
        return Ok(());
    }
    validate_source(target)
}

/// Change only the owned guideline property to the value required by local cosmetics.
/// Unknown fields and formatting-independent JSON data are retained.
pub fn ensure_local_mode(state_root: &Path, target: &Path) -> Result<()> {
    let config = core_path(target);
    let (_, mut document) = current_source(target)?;
    let ownership = ownership_path(state_root, target);

    if let Some(record) = read_record(&ownership)? {
        ensure_record_target(&record, target)?;
    } else {
        let record = if config.is_file() {
            record_for_document(target, &document)?
        } else {
            record_for_missing_document(target)
        };
        write_record(&ownership, &record)?;
    }

    let object = document.as_object_mut().ok_or_else(|| {
        AppError::launch(format!(
            "CounterStrikeSharp core.json must contain a JSON object ({}).",
            config.display()
        ))
    })?;
    object.insert(GUIDELINES_FIELD.to_string(), Value::Bool(false));
    write_json(&config, &document)
}

pub fn snapshot_current(target: &Path) -> Result<Option<Value>> {
    let config = core_path(target);
    if !config.is_file() {
        return Ok(None);
    }
    let bytes = fs::read(&config).map_err(AppError::transaction_io)?;
    Ok(serde_json::from_slice(&bytes).ok())
}

/// Restore only the field owned by this app. If the original document did not exist, remove the
/// package-created core.json; otherwise keep unknown fields added after the local-mode change.
pub fn restore_owned_with_current(
    state_root: &Path,
    target: &Path,
    current_snapshot: Option<Option<Value>>,
) -> Result<()> {
    let ownership = ownership_path(state_root, target);
    let Some(record) = read_record(&ownership)? else {
        return Ok(());
    };
    ensure_record_target(&record, target)?;
    let config = core_path(target);

    match record.original_document {
        Some(original_document) => {
            let current = match current_snapshot {
                Some(value) => value,
                None => snapshot_current(target)?,
            };
            match current {
                Some(mut current) if current.is_object() => {
                    let object = current.as_object_mut().expect("checked above");
                    match record.original_guidelines {
                        Some(value) => {
                            object.insert(GUIDELINES_FIELD.to_string(), value);
                        }
                        None => {
                            object.remove(GUIDELINES_FIELD);
                        }
                    }
                    write_json(&config, &current)?;
                }
                _ => write_json(&config, &original_document)?,
            }
        }
        None => {
            if config.is_file() {
                fs::remove_file(&config).map_err(AppError::transaction_io)?;
            }
        }
    }
    discard_capture(state_root, target)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn root(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!("cs2bi-core-config-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn local_mode_changes_one_field_and_restore_keeps_unknown_updates() {
        let base = root("preserve");
        let state = base.join("state");
        let target = base.join("game/csgo");
        let config = core_path(&target);
        fs::create_dir_all(config.parent().unwrap()).unwrap();
        fs::write(&config, br#"{"FollowCS2ServerGuidelines":true,"PluginHotReload":false,"Unknown":{"keep":1}}"#).unwrap();

        assert!(capture_before_install(&state, &target).unwrap());
        ensure_local_mode(&state, &target).unwrap();
        let mut current = read_json(&config, "test").unwrap();
        assert_eq!(current[GUIDELINES_FIELD], Value::Bool(false));
        current["Unknown"]["changed_after_launch"] = Value::Bool(true);
        write_json(&config, &current).unwrap();

        restore_owned_with_current(&state, &target, None).unwrap();
        let restored = read_json(&config, "test").unwrap();
        assert_eq!(restored[GUIDELINES_FIELD], Value::Bool(true));
        assert_eq!(restored["Unknown"]["changed_after_launch"], Value::Bool(true));
        assert!(!ownership_path(&state, &target).exists());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn missing_core_derives_from_example_and_removes_owned_file_on_restore() {
        let base = root("example");
        let state = base.join("state");
        let target = base.join("game/csgo");
        let example = core_example_path(&target);
        fs::create_dir_all(example.parent().unwrap()).unwrap();
        fs::write(&example, br#"{"FollowCS2ServerGuidelines":true,"Unknown":1}"#).unwrap();

        ensure_local_mode(&state, &target).unwrap();
        let current = read_json(&core_path(&target), "test").unwrap();
        assert_eq!(current[GUIDELINES_FIELD], Value::Bool(false));
        restore_owned_with_current(&state, &target, None).unwrap();
        assert!(!core_path(&target).exists());
        assert!(example.is_file());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn malformed_core_fails_closed() {
        let base = root("malformed");
        let target = base.join("game/csgo");
        let config = core_path(&target);
        fs::create_dir_all(config.parent().unwrap()).unwrap();
        fs::write(&config, b"[]").unwrap();
        let error = validate_source(&target).unwrap_err();
        assert!(error.detail.contains("JSON object"));
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn missing_source_fails_closed() {
        let base = root("missing");
        let error = validate_source(&base.join("game/csgo")).unwrap_err();
        assert!(error.detail.contains("core.example.json"));
        fs::remove_dir_all(base).unwrap();
    }
}
