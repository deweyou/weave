export interface AppInfo {
  name: string;
  version: string;
}

export interface RuntimeStatus {
  agentBaseUrl: string;
  dataRoot: string;
}

export interface LocalPaths {
  dataRoot: string;
  profiles: string;
  sessions: string;
  drafts: string;
  memory: string;
  indexes: string;
  logs: string;
}

export interface HealthResponse {
  status: "ok";
  service: string;
  version: string;
}

export interface DiscoverResponse {
  stage: "discover";
  summary: string;
  questions: string[];
}
