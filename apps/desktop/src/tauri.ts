import { invoke } from "@tauri-apps/api/core";

import type {
  AppInfo,
  DiscoverResponse,
  HealthResponse,
  LocalPaths,
  RuntimeStatus,
} from "./types";

export function getAppInfo(): Promise<AppInfo> {
  return invoke<AppInfo>("get_app_info");
}

export function getRuntimeStatus(): Promise<RuntimeStatus> {
  return invoke<RuntimeStatus>("get_runtime_status");
}

export function getLocalPaths(): Promise<LocalPaths> {
  return invoke<LocalPaths>("get_local_paths");
}

export function agentHealthCheck(): Promise<HealthResponse> {
  return invoke<HealthResponse>("agent_health_check");
}

export function agentDiscover(input: string): Promise<DiscoverResponse> {
  return invoke<DiscoverResponse>("agent_discover", { input });
}
