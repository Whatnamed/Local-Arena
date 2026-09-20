use crate::atomic_fs;
use crate::installer::installation_dir;
use crate::{AppError, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

pub const GUIDELINES_PROPERTY: &str = "FollowCS2ServerGuidelines";
pub const CORE_JSON_REL: &str = "addons/counterstrikesharp/configs/core.json";
pub const CORE_EXAMPLE_JSON_REL: &str = "addons/counterstrikesharp/configs/core.example.json";
pub const OWNERSHIP_FILE: &str = "guidelines_ownership.json";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GuidelinesOwnership {
    pub schema_version: u32,
    pub core_json_existed: bool,
    pub property_existed: bool,
    pub original_value: Option<bool>,
}

pub fn core_json_path(csgo_root: &Path) -> PathBuf {
    csgo_root.join(CORE_JSON_REL)
}

pub fn core_example_json_path(csgo_root: &Path) -> PathBuf {
    csgo_root.join(CORE_EXAMPLE_JSON_REL)
}

pub fn ownership_path(state_root: &Path, csgo_root: &Path) -> PathBuf {
    installation_dir(state_root, csgo_root).join(OWNERSHIP_FILE)
}

fn read_ownership(path: &Path) -> Option<GuidelinesOwnership> {
    let bytes = fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn write_ownership(path: &Path, record: &GuidelinesOwnership) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(record)
        .map_err(|e| AppError::config(format!("Failed to serialize guidelines ownership: {e}")))?;
    atomic_fs::write_replace(path, &bytes)
        .map_err(AppError::transaction_io)
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum ReconcileAction {
    CreatedFromExample,
    UpdatedProperty,
    AlreadyCompliant,
}

pub(crate) fn reconcile_core_json(csgo_root: &Path, state_root: Option<&Path>) -> Result<ReconcileAction> {
    let core = core_json_path(csgo_root);
    let example = core_example_json_path(csgo_root);
    let own_file = state_root.map(|sr| ownership_path(sr, csgo_root));

    if !core.is_file() {
        // File does not exist yet.
        // Record ownership before creating: core.json did not exist originally.
        if let Some(own_path) = &own_file {
            if !own_path.is_file() {
                write_ownership(
                    own_path,
                    &GuidelinesOwnership {
                        schema_version: 1,
                        core_json_existed: false,
                        property_existed: false,
                        original_value: None,
                    },
                )?;
            }
        }

        if !example.is_file() {
            return Err(AppError::config(format!(
                "CounterStrikeSharp core.example.json template is missing at {}; cannot safely generate core.json",
                example.display()
            )));
        }

        let example_bytes = fs::read(&example)
            .map_err(|e| AppError::config(format!("Cannot read core.example.json: {e}")))?;
        let mut doc: Value = serde_json::from_slice(&example_bytes).map_err(|e| {
            AppError::config(format!("core.example.json is malformed JSON: {e}"))
        })?;

        let map = doc.as_object_mut().ok_or_else(|| {
            AppError::config("core.example.json root must be a JSON object")
        })?;

        map.insert(GUIDELINES_PROPERTY.to_string(), Value::Bool(false));

        let formatted = serde_json::to_vec_pretty(&doc).map_err(|e| {
            AppError::config(format!("Failed to serialize generated core.json: {e}"))
        })?;
        atomic_fs::write_replace(&core, &formatted).map_err(AppError::transaction_io)?;
        return Ok(ReconcileAction::CreatedFromExample);
    }

    // core.json already exists. Read and parse it preserving all unknown fields.
    let core_bytes = fs::read(&core)
        .map_err(|e| AppError::config(format!("Cannot read core.json: {e}")))?;
    let mut doc: Value = serde_json::from_slice(&core_bytes).map_err(|e| {
        AppError::config(format!(
            "addons/counterstrikesharp/configs/core.json is malformed JSON: {e}"
        ))
    })?;

    let map = doc.as_object_mut().ok_or_else(|| {
        AppError::config("core.json root must be a JSON object")
    })?;

    let existing_val = map.get(GUIDELINES_PROPERTY);
    let prop_existed = existing_val.is_some();
    let orig_bool = existing_val.and_then(Value::as_bool);

    // Record ownership if not recorded yet
    if let Some(own_path) = &own_file {
        if !own_path.is_file() {
            write_ownership(
                own_path,
                &GuidelinesOwnership {
                    schema_version: 1,
                    core_json_existed: true,
                    property_existed: prop_existed,
                    original_value: orig_bool,
                },
            )?;
        }
    }

    if existing_val == Some(&Value::Bool(false)) {
        return Ok(ReconcileAction::AlreadyCompliant);
    }

    // Set FollowCS2ServerGuidelines = false
    map.insert(GUIDELINES_PROPERTY.to_string(), Value::Bool(false));

    let formatted = serde_json::to_vec_pretty(&doc).map_err(|e| {
        AppError::config(format!("Failed to serialize reconciled core.json: {e}"))
    })?;
    atomic_fs::write_replace(&core, &formatted).map_err(AppError::transaction_io)?;
    Ok(ReconcileAction::UpdatedProperty)
}

pub(crate) fn restore_core_json(csgo_root: &Path, state_root: &Path) -> Result<()> {
    let own_path = ownership_path(state_root, csgo_root);
    let Some(ownership) = read_ownership(&own_path) else {
        return Ok(());
    };

    let core = core_json_path(csgo_root);
    if !ownership.core_json_existed {
        // We created core.json; remove it cleanly if it exists
        if core.is_file() {
            let _ = fs::remove_file(&core);
        }
    } else if core.is_file() {
        // File existed before. Restore only the property.
        if let Ok(bytes) = fs::read(&core) {
            if let Ok(mut doc) = serde_json::from_slice::<Value>(&bytes) {
                if let Some(map) = doc.as_object_mut() {
                    if ownership.property_existed {
                        map.insert(
                            GUIDELINES_PROPERTY.to_string(),
                            Value::Bool(ownership.original_value.unwrap_or(true)),
                        );
                    } else {
                        map.remove(GUIDELINES_PROPERTY);
                    }
                    if let Ok(formatted) = serde_json::to_vec_pretty(&doc) {
                        let _ = atomic_fs::write_replace(&core, &formatted);
                    }
                }
            }
        }
    }

    let _ = fs::remove_file(&own_path);
    Ok(())
}

pub(crate) fn is_guidelines_compliant(csgo_root: &Path) -> Result<bool> {
    let core = core_json_path(csgo_root);
    if !core.is_file() {
        return Ok(false);
    }
    let bytes = fs::read(&core).map_err(|e| AppError::config(format!("Cannot read core.json: {e}")))?;
    let doc: Value = serde_json::from_slice(&bytes)
        .map_err(|e| AppError::config(format!("core.json is malformed JSON: {e}")))?;
    let map = doc.as_object().ok_or_else(|| AppError::config("core.json root must be a JSON object"))?;
    Ok(map.get(GUIDELINES_PROPERTY) == Some(&Value::Bool(false)))
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestDir(PathBuf);
    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn setup_env() -> (TestDir, PathBuf, PathBuf) {
        use std::time::{SystemTime, UNIX_EPOCH};
        let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let temp = std::env::temp_dir().join(format!("cs2bi-guidelines-test-{nanos}"));
        let _ = fs::remove_dir_all(&temp);
        let csgo = temp.join("csgo");
        let state = temp.join("state");
        let configs = csgo.join("addons/counterstrikesharp/configs");
        fs::create_dir_all(&configs).unwrap();
        fs::create_dir_all(&state).unwrap();
        (TestDir(temp), csgo, state)
    }

    #[test]
    fn missing_core_json_generates_from_example_with_false() {
        let (_tmp, csgo, state) = setup_env();
        let example = core_example_json_path(&csgo);
        fs::write(
            &example,
            r#"{ "FollowCS2ServerGuidelines": true, "CustomPluginSetting": 42 }"#,
        )
        .unwrap();

        let action = reconcile_core_json(&csgo, Some(&state)).unwrap();
        assert_eq!(action, ReconcileAction::CreatedFromExample);

        let core = core_json_path(&csgo);
        assert!(core.is_file());
        let val: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val["FollowCS2ServerGuidelines"], false);
        assert_eq!(val["CustomPluginSetting"], 42);

        let own = read_ownership(&ownership_path(&state, &csgo)).unwrap();
        assert_eq!(own.core_json_existed, false);
        assert_eq!(own.property_existed, false);
        assert_eq!(own.original_value, None);
    }

    #[test]
    fn missing_core_json_and_missing_example_fails_closed() {
        let (_tmp, csgo, state) = setup_env();
        let err = reconcile_core_json(&csgo, Some(&state)).unwrap_err();
        assert!(err.detail.contains("template is missing"));
    }

    #[test]
    fn existing_true_is_reconciled_to_false_and_preserves_unknown_fields() {
        let (_tmp, csgo, state) = setup_env();
        let core = core_json_path(&csgo);
        fs::write(
            &core,
            r#"{ "FollowCS2ServerGuidelines": true, "FutureField": { "Nested": true }, "Count": 100 }"#,
        )
        .unwrap();

        let action = reconcile_core_json(&csgo, Some(&state)).unwrap();
        assert_eq!(action, ReconcileAction::UpdatedProperty);

        let val: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val["FollowCS2ServerGuidelines"], false);
        assert_eq!(val["FutureField"]["Nested"], true);
        assert_eq!(val["Count"], 100);

        let own = read_ownership(&ownership_path(&state, &csgo)).unwrap();
        assert_eq!(own.core_json_existed, true);
        assert_eq!(own.property_existed, true);
        assert_eq!(own.original_value, Some(true));
    }

    #[test]
    fn existing_false_remains_unchanged() {
        let (_tmp, csgo, state) = setup_env();
        let core = core_json_path(&csgo);
        fs::write(
            &core,
            r#"{ "FollowCS2ServerGuidelines": false, "Other": 1 }"#,
        )
        .unwrap();

        let action = reconcile_core_json(&csgo, Some(&state)).unwrap();
        assert_eq!(action, ReconcileAction::AlreadyCompliant);

        let val: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val["FollowCS2ServerGuidelines"], false);
    }

    #[test]
    fn missing_property_in_existing_file_adds_false_and_records_absence() {
        let (_tmp, csgo, state) = setup_env();
        let core = core_json_path(&csgo);
        fs::write(&core, r#"{ "ServerLanguage": "zh-Hans" }"#).unwrap();

        let action = reconcile_core_json(&csgo, Some(&state)).unwrap();
        assert_eq!(action, ReconcileAction::UpdatedProperty);

        let val: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val["FollowCS2ServerGuidelines"], false);
        assert_eq!(val["ServerLanguage"], "zh-Hans");

        let own = read_ownership(&ownership_path(&state, &csgo)).unwrap();
        assert_eq!(own.core_json_existed, true);
        assert_eq!(own.property_existed, false);
        assert_eq!(own.original_value, None);
    }

    #[test]
    fn malformed_json_fails_closed() {
        let (_tmp, csgo, state) = setup_env();
        let core = core_json_path(&csgo);
        fs::write(&core, b"{ not json }").unwrap();

        let err = reconcile_core_json(&csgo, Some(&state)).unwrap_err();
        assert!(err.detail.contains("malformed JSON"));
    }

    #[test]
    fn restore_cleans_up_created_core_json() {
        let (_tmp, csgo, state) = setup_env();
        let example = core_example_json_path(&csgo);
        fs::write(&example, r#"{ "FollowCS2ServerGuidelines": true }"#).unwrap();

        reconcile_core_json(&csgo, Some(&state)).unwrap();
        let core = core_json_path(&csgo);
        assert!(core.is_file());

        restore_core_json(&csgo, &state).unwrap();
        assert!(!core.is_file());
        assert!(!ownership_path(&state, &csgo).is_file());
    }

    #[test]
    fn restore_returns_original_true_value() {
        let (_tmp, csgo, state) = setup_env();
        let core = core_json_path(&csgo);
        fs::write(
            &core,
            r#"{ "FollowCS2ServerGuidelines": true, "KeepMe": 99 }"#,
        )
        .unwrap();

        reconcile_core_json(&csgo, Some(&state)).unwrap();
        let val_mid: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val_mid["FollowCS2ServerGuidelines"], false);

        restore_core_json(&csgo, &state).unwrap();
        let val_end: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val_end["FollowCS2ServerGuidelines"], true);
        assert_eq!(val_end["KeepMe"], 99);
    }

    #[test]
    fn restore_removes_property_if_originally_absent() {
        let (_tmp, csgo, state) = setup_env();
        let core = core_json_path(&csgo);
        fs::write(&core, r#"{ "KeepMe": 99 }"#).unwrap();

        reconcile_core_json(&csgo, Some(&state)).unwrap();
        let val_mid: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val_mid["FollowCS2ServerGuidelines"], false);

        restore_core_json(&csgo, &state).unwrap();
        let val_end: Value = serde_json::from_slice(&fs::read(&core).unwrap()).unwrap();
        assert_eq!(val_end.get("FollowCS2ServerGuidelines"), None);
        assert_eq!(val_end["KeepMe"], 99);
    }
}
