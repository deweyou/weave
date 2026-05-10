use serde::Serialize;
use std::{fs, path::PathBuf};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalPaths {
    pub data_root: String,
    pub profiles: String,
    pub sessions: String,
    pub drafts: String,
    pub memory: String,
    pub indexes: String,
    pub logs: String,
}

pub fn initialize_local_paths() -> Result<LocalPaths, String> {
    let data_root = repo_data_root()?;
    let paths = LocalPaths {
        profiles: data_root.join("profiles").display().to_string(),
        sessions: data_root.join("sessions").display().to_string(),
        drafts: data_root.join("drafts").display().to_string(),
        memory: data_root.join("memory").display().to_string(),
        indexes: data_root.join("indexes").display().to_string(),
        logs: data_root.join("logs").display().to_string(),
        data_root: data_root.display().to_string(),
    };

    for path in [
        &paths.data_root,
        &paths.profiles,
        &paths.sessions,
        &paths.drafts,
        &paths.memory,
        &paths.indexes,
        &paths.logs,
    ] {
        fs::create_dir_all(path).map_err(|error| format!("failed to create {path}: {error}"))?;
    }

    let default_profile = data_root.join("profiles").join("default.json");
    if !default_profile.exists() {
        fs::write(
            &default_profile,
            serde_json::json!({
                "id": "default",
                "name": "Default",
                "description": "Default writing profile",
                "style_preferences": [],
                "memory_namespace": "default",
                "knowledge_sources": []
            })
            .to_string(),
        )
        .map_err(|error| format!("failed to write default profile: {error}"))?;
    }

    Ok(paths)
}

fn repo_data_root() -> Result<PathBuf, String> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo_root = manifest_dir
        .parent()
        .and_then(|path| path.parent())
        .and_then(|path| path.parent())
        .ok_or_else(|| "failed to resolve repository root".to_string())?;
    Ok(repo_root.join("data"))
}
