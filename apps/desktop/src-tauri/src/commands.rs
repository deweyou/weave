use serde::Serialize;

use crate::{
    agent::{agent_base_url, discover, health_check, DiscoverResponse, HealthResponse},
    storage::{initialize_local_paths, LocalPaths},
};

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
        agent_base_url: agent_base_url().to_string(),
        data_root: paths.data_root,
    })
}

#[tauri::command]
pub fn get_local_paths() -> Result<LocalPaths, String> {
    initialize_local_paths()
}

#[tauri::command]
pub async fn agent_health_check() -> Result<HealthResponse, String> {
    health_check().await
}

#[tauri::command]
pub async fn agent_discover(input: String) -> Result<DiscoverResponse, String> {
    discover(input).await
}
