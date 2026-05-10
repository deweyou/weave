use serde::Serialize;

use crate::storage::{initialize_local_paths, LocalPaths};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppInfo {
    pub name: String,
    pub version: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeStatus {
    pub agent_base_url: String,
    pub data_root: String,
}

#[tauri::command]
pub fn get_app_info() -> AppInfo {
    AppInfo {
        name: "Weave".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    }
}

#[tauri::command]
pub fn get_runtime_status() -> Result<RuntimeStatus, String> {
    let paths = initialize_local_paths()?;
    Ok(RuntimeStatus {
        agent_base_url: "http://127.0.0.1:8765".to_string(),
        data_root: paths.data_root,
    })
}

#[tauri::command]
pub fn get_local_paths() -> Result<LocalPaths, String> {
    initialize_local_paths()
}
