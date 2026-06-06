import type { WorkspaceSummary } from "./starter-workspace";

export interface AppShellProps {
  readonly workspace: WorkspaceSummary;
  readonly runtimeName: string;
}

export function AppShell({ workspace, runtimeName }: AppShellProps) {
  return (
    <main className="app-shell">
      <header className="hero">
        <p className="eyebrow">{runtimeName} / local-first workspace</p>
        <h1>Weave</h1>
      </header>

      <section className="entry-grid" aria-label={workspace.name}>
        {workspace.entries.map((entry) => (
          <article className="entry-card" key={entry.id}>
            <p className="entry-meta">
              {entry.kind.toUpperCase()} · {entry.updatedAt}
            </p>
            <h2>{entry.title}</h2>
            <p>{entry.summary}</p>
          </article>
        ))}
      </section>
    </main>
  );
}
