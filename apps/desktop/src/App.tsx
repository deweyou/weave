import { useEffect, useMemo, useState } from "react";

import {
  agentDiscover,
  agentHealthCheck,
  getAppInfo,
  getLocalPaths,
  getRuntimeStatus,
} from "./tauri";
import type { AppInfo, DiscoverResponse, HealthResponse, LocalPaths, RuntimeStatus } from "./types";

type LoadState = "idle" | "loading" | "ready" | "error";

export default function App() {
  const [appInfo, setAppInfo] = useState<AppInfo | null>(null);
  const [runtime, setRuntime] = useState<RuntimeStatus | null>(null);
  const [paths, setPaths] = useState<LocalPaths | null>(null);
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [input, setInput] = useState("我想写一篇关于 agent 产品为什么不能只是聊天壳的文章");
  const [discover, setDiscover] = useState<DiscoverResponse | null>(null);
  const [state, setState] = useState<LoadState>("idle");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void refreshStatus();
  }, []);

  const canDiscover = useMemo(() => input.trim().length > 0 && state !== "loading", [input, state]);

  async function refreshStatus() {
    setState("loading");
    setError(null);
    try {
      const [info, runtimeStatus, localPaths] = await Promise.all([
        getAppInfo(),
        getRuntimeStatus(),
        getLocalPaths(),
      ]);
      setAppInfo(info);
      setRuntime(runtimeStatus);
      setPaths(localPaths);

      try {
        setHealth(await agentHealthCheck());
      } catch (healthError) {
        setHealth(null);
        setError(toErrorMessage(healthError));
      }

      setState("ready");
    } catch (statusError) {
      setState("error");
      setError(toErrorMessage(statusError));
    }
  }

  async function runDiscover() {
    if (!input.trim()) {
      setError("Enter a writing idea first.");
      return;
    }

    setState("loading");
    setError(null);
    setDiscover(null);
    try {
      const result = await agentDiscover(input.trim());
      setDiscover(result);
      setState("ready");
    } catch (discoverError) {
      setState("error");
      setError(toErrorMessage(discoverError));
    }
  }

  return (
    <main className="shell">
      <section className="header">
        <div>
          <p className="eyebrow">Phase 0</p>
          <h1>{appInfo?.name ?? "Weave"}</h1>
        </div>
        <button type="button" onClick={() => void refreshStatus()}>
          Refresh
        </button>
      </section>

      <section className="statusGrid">
        <StatusItem label="App version" value={appInfo?.version ?? "unknown"} />
        <StatusItem label="Agent URL" value={runtime?.agentBaseUrl ?? "unknown"} />
        <StatusItem label="Agent health" value={health ? `${health.service} ${health.version}` : "unavailable"} />
        <StatusItem label="Data root" value={paths?.dataRoot ?? runtime?.dataRoot ?? "unknown"} />
      </section>

      {error ? <p className="error">{error}</p> : null}

      <section className="panel">
        <label htmlFor="writing-input">Writing idea</label>
        <textarea
          id="writing-input"
          value={input}
          onChange={(event) => setInput(event.target.value)}
          rows={5}
        />
        <button type="button" disabled={!canDiscover} onClick={() => void runDiscover()}>
          Discover
        </button>
      </section>

      {discover ? (
        <section className="panel">
          <p className="eyebrow">{discover.stage}</p>
          <h2>Summary</h2>
          <p>{discover.summary}</p>
          <h2>Questions</h2>
          <ol>
            {discover.questions.map((question) => (
              <li key={question}>{question}</li>
            ))}
          </ol>
        </section>
      ) : null}
    </main>
  );
}

function StatusItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="statusItem">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function toErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}
