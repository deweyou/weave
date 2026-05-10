use serde::{Deserialize, Serialize};

const AGENT_BASE_URL: &str = "http://127.0.0.1:8765";

#[derive(Debug, Deserialize, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub service: String,
    pub version: String,
}

#[derive(Debug, Serialize)]
pub struct DiscoverRequest {
    pub input: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct DiscoverResponse {
    pub stage: String,
    pub summary: String,
    pub questions: Vec<String>,
}

pub fn agent_base_url() -> &'static str {
    AGENT_BASE_URL
}

pub async fn health_check() -> Result<HealthResponse, String> {
    let url = format!("{AGENT_BASE_URL}/health");
    let response = reqwest::get(url)
        .await
        .map_err(|error| format!("agent service unavailable: {error}"))?;

    if !response.status().is_success() {
        return Err(format!("agent health check failed: {}", response.status()));
    }

    response
        .json::<HealthResponse>()
        .await
        .map_err(|error| format!("invalid agent health response: {error}"))
}

pub async fn discover(input: String) -> Result<DiscoverResponse, String> {
    if input.trim().is_empty() {
        return Err("writing idea cannot be empty".to_string());
    }

    let client = reqwest::Client::new();
    let response = client
        .post(format!("{AGENT_BASE_URL}/writing/discover"))
        .json(&DiscoverRequest { input })
        .send()
        .await
        .map_err(|error| format!("agent service unavailable: {error}"))?;

    if !response.status().is_success() {
        return Err(format!("agent discover failed: {}", response.status()));
    }

    response
        .json::<DiscoverResponse>()
        .await
        .map_err(|error| format!("invalid agent discover response: {error}"))
}
