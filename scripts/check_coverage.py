#!/usr/bin/env python3
"""Gate LLVM line coverage. Every app source participates in the overall gate."""
import argparse
import json
from pathlib import Path

# UI declarations are covered by XCUITest separately; never hide them in totals.
UI_FILES = {"WeaveApp.swift", "WorkspaceView.swift"}
BRIDGE_FILES = {"NativeRichTextEditor.swift"}
THRESHOLDS = {"all": 35.0, "core": 90.0, "bridge": 55.0}


def evaluate(report, source_root):
    source_root = source_root.resolve()
    expected = {p.resolve() for p in source_root.rglob("*.swift")}
    if not expected:
        raise ValueError("No Swift sources found")
    found = {}
    for data in report["data"]:
        for entry in data["files"]:
            path = Path(entry["filename"]).resolve()
            if path in expected:
                if path in found:
                    raise ValueError(f"Duplicate coverage entry: {path}")
                lines = entry["summary"]["lines"]
                count, covered = lines["count"], lines["covered"]
                if count <= 0 or not 0 <= covered <= count:
                    raise ValueError(f"Invalid line counts: {path}")
                found[path] = (covered, count)
    if expected != found.keys():
        raise ValueError(f"Missing coverage: {sorted(str(p) for p in expected - found.keys())}")
    groups = {
        "all": list(found),
        "core": [p for p in found if p.name not in UI_FILES | BRIDGE_FILES],
        "bridge": [p for p in found if p.name in BRIDGE_FILES],
    }
    rows, passed = [], True
    for name, paths in groups.items():
        count = sum(found[p][1] for p in paths)
        if not count:
            raise ValueError(f"Empty coverage group: {name}")
        covered = sum(found[p][0] for p in paths)
        percent = covered * 100 / count
        threshold = THRESHOLDS[name]
        passed &= percent >= threshold
        rows.append(f"| {name} | {covered}/{count} | {percent:.2f}% | {threshold:.0f}% | {'PASS' if percent >= threshold else 'FAIL'} |")
    for path, (covered, count) in sorted(found.items()):
        rows.append(f"| {path.name} | {covered}/{count} | {covered * 100 / count:.2f}% | — | — |")
    return passed, "\n".join(["# Unit test line coverage", "", "| Scope | Lines | Coverage | Minimum | Status |", "| --- | --- | --- | --- | --- |", *rows, ""])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--sources", type=Path, default=Path("Sources/Weave"))
    parser.add_argument("--output", type=Path, default=Path(".build/coverage-summary.md"))
    args = parser.parse_args()
    try:
        passed, summary = evaluate(json.loads(args.report.read_text()), args.sources)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, f"Coverage failed: {error}\n")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(summary)
    print(summary)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
