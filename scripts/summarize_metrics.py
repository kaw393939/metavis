#!/usr/bin/env python3

import argparse
import json
import os
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def _read_jsonl(path: Path):
    if not path.exists():
        return []
    out = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                # Ignore malformed lines (partial writes, etc.)
                continue
    return out


def _fmt_ms(v):
    return "" if v is None else f"{v:.2f}"


def _fmt(v, places=6):
    return "" if v is None else f"{v:.{places}f}"


def _safe(s):
    return s if s is not None else ""


def main():
    ap = argparse.ArgumentParser(description="Summarize perf+color events for a given runID")
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--repo-root", default=None)
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parents[1]
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    perf_jsonl = repo_root / "test_outputs" / "perf" / "perf.jsonl"
    events = [e for e in _read_jsonl(perf_jsonl) if e.get("runID") == args.run_id]

    # Persist immutable slice for the run.
    events_jsonl = out_dir / "events.jsonl"
    with events_jsonl.open("w", encoding="utf-8") as f:
        for e in events:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    # Build summary.
    header = {
        "runID": args.run_id,
        "count": len(events),
        "generatedUTC": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "osVersion": events[0].get("osVersion") if events else None,
        "arch": events[0].get("processArch") if events else None,
        "firstTimestamp": events[0].get("timestampISO8601") if events else None,
    }

    perf_rows = []
    mem_rows = []
    color_rows = []
    studio_rows = []
    ocio_rows = []

    # Prefer last event per (suite,label,width,height,test) in case repeats happened.
    last_by_key = {}
    for e in events:
        key = (
            e.get("suite"),
            e.get("label"),
            e.get("width"),
            e.get("height"),
            e.get("test"),
        )
        last_by_key[key] = e

    for e in last_by_key.values():
        suite = e.get("suite")
        label = e.get("label")

        if e.get("avgMs") is not None:
            perf_rows.append(
                {
                    "suite": suite,
                    "label": label,
                    "w": e.get("width"),
                    "h": e.get("height"),
                    "frames": e.get("frames"),
                    "avgMs": e.get("avgMs"),
                    "test": e.get("test"),
                }
            )

        if e.get("peakRSSDeltaMB") is not None:
            mem_rows.append(
                {
                    "suite": suite,
                    "label": label,
                    "peakRSSDeltaMB": e.get("peakRSSDeltaMB"),
                    "message": e.get("message"),
                    "test": e.get("test"),
                }
            )

        if e.get("deltaE2000Avg") is not None or e.get("deltaE2000Max") is not None:
            color_rows.append(
                {
                    "suite": suite,
                    "label": label,
                    "deltaEAvg": e.get("deltaE2000Avg"),
                    "deltaEMax": e.get("deltaE2000Max"),
                    "worst": e.get("deltaEWorstPatch"),
                    "test": e.get("test"),
                }
            )

        if e.get("lutMeanAbsErr") is not None or e.get("lutMaxAbsErr") is not None:
            studio_rows.append(
                {
                    "suite": suite,
                    "label": label,
                    "meanAbs": e.get("lutMeanAbsErr"),
                    "maxAbs": e.get("lutMaxAbsErr"),
                    "worst": e.get("lutWorstPatch"),
                    "test": e.get("test"),
                }
            )

        if e.get("ocioBakeMeanAbsErr") is not None or e.get("ocioBakeMaxAbsErr") is not None:
            ocio_rows.append(
                {
                    "suite": suite,
                    "label": label,
                    "name": e.get("ocioBakeName"),
                    "meanAbs": e.get("ocioBakeMeanAbsErr"),
                    "maxAbs": e.get("ocioBakeMaxAbsErr"),
                    "test": e.get("test"),
                }
            )

    perf_rows.sort(key=lambda r: (r["label"] or "", r["h"] or 0))
    mem_rows.sort(key=lambda r: (r["label"] or "", r["test"] or ""))
    color_rows.sort(key=lambda r: (r["label"] or "", r["test"] or ""))
    studio_rows.sort(key=lambda r: (r["label"] or "", r["test"] or ""))
    ocio_rows.sort(key=lambda r: (_safe(r["name"]), r["test"] or ""))

    summary_md = out_dir / "summary.md"
    with summary_md.open("w", encoding="utf-8") as f:
        f.write(f"# MetaVis Metrics Run\n\n")
        f.write(f"- runID: `{header['runID']}`\n")
        f.write(f"- events: `{header['count']}`\n")
        if header.get("osVersion"):
            f.write(f"- os: `{header['osVersion']}`\n")
        if header.get("arch"):
            f.write(f"- arch: `{header['arch']}`\n")
        if header.get("generatedUTC"):
            f.write(f"- generatedUTC: `{header['generatedUTC']}`\n")
        f.write("\n")

        f.write("## Performance\n\n")
        if not perf_rows:
            f.write("(no perf events found for this run)\n\n")
        else:
            f.write("| label | res | frames | avgMs | suite | test |\n")
            f.write("|---|---:|---:|---:|---|---|\n")
            for r in perf_rows:
                res = f"{r['w']}x{r['h']}" if r.get("w") and r.get("h") else ""
                f.write(
                    f"| {_safe(r['label'])} | {res} | {r.get('frames','')} | {_fmt_ms(r['avgMs'])} | {_safe(r['suite'])} | {_safe(r['test'])} |\n"
                )
            f.write("\n")

        f.write("## Memory\n\n")
        if not mem_rows:
            f.write("(no memory events found for this run)\n\n")
        else:
            f.write("| label | peakRSSDeltaMB | message | suite | test |\n")
            f.write("|---|---:|---|---|---|\n")
            for r in mem_rows:
                f.write(
                    f"| {_safe(r['label'])} | {_fmt(r['peakRSSDeltaMB'], places=3)} | {_safe(r['message'])} | {_safe(r['suite'])} | {_safe(r['test'])} |\n"
                )
            f.write("\n")

        f.write("## Color (ΔE2000)\n\n")
        if not color_rows:
            f.write("(no ΔE events found for this run)\n\n")
        else:
            f.write("| label | ΔE avg | ΔE max | worst | suite | test |\n")
            f.write("|---|---:|---:|---|---|---|\n")
            for r in color_rows:
                f.write(
                    f"| {_safe(r['label'])} | {_fmt(r['deltaEAvg'], places=4)} | {_fmt(r['deltaEMax'], places=4)} | {_safe(r['worst'])} | {_safe(r['suite'])} | {_safe(r['test'])} |\n"
                )
            f.write("\n")

        f.write("## Studio LUT Reference Match\n\n")
        if not studio_rows:
            f.write("(no Studio LUT match events found for this run)\n\n")
        else:
            f.write("| label | meanAbsErr | maxAbsErr | worst | suite | test |\n")
            f.write("|---|---:|---:|---|---|---|\n")
            for r in studio_rows:
                f.write(
                    f"| {_safe(r['label'])} | {_fmt(r['meanAbs'], places=8)} | {_fmt(r['maxAbs'], places=8)} | {_safe(r['worst'])} | {_safe(r['suite'])} | {_safe(r['test'])} |\n"
                )
            f.write("\n")

        f.write("## OCIO Re-bake Match\n\n")
        if not ocio_rows:
            f.write("(no OCIO bake match events found for this run)\n\n")
        else:
            f.write("| name | meanAbsErr | maxAbsErr | suite | test |\n")
            f.write("|---|---:|---:|---|---|\n")
            for r in ocio_rows:
                f.write(
                    f"| {_safe(r['name'])} | {_fmt(r['meanAbs'], places=10)} | {_fmt(r['maxAbs'], places=10)} | {_safe(r['suite'])} | {_safe(r['test'])} |\n"
                )
            f.write("\n")

        f.write("## Files\n\n")
        rel_events = os.path.relpath(events_jsonl, repo_root)
        rel_summary = os.path.relpath(summary_md, repo_root)
        f.write(f"- events: `{rel_events}`\n")
        f.write(f"- summary: `{rel_summary}`\n")

    # Update a simple index for historical tracking.
    metrics_root = repo_root / "test_outputs" / "metrics"
    metrics_root.mkdir(parents=True, exist_ok=True)
    index_md = metrics_root / "README.md"

    if not index_md.exists():
        index_md.write_text(
            "# Metrics Runs\n\n"
            "Each run is stored under `test_outputs/metrics/<runID>/`.\n\n"
            "Run with: `scripts/run_metrics.sh`\n\n"
            "## Runs\n\n",
            encoding="utf-8",
        )

    rel_run = os.path.relpath(out_dir, metrics_root)
    line = f"- `{args.run_id}`: `{rel_run}/summary.md`\n"

    existing = index_md.read_text(encoding="utf-8")
    if line not in existing:
        # Append newest at the top of the Runs section if possible.
        parts = existing.split("## Runs\n\n", 1)
        if len(parts) == 2:
            head, rest = parts
            index_md.write_text(head + "## Runs\n\n" + line + rest, encoding="utf-8")
        else:
            index_md.write_text(existing + "\n" + line, encoding="utf-8")

    print(f"[summarize_metrics] wrote: {summary_md}")
    print(f"[summarize_metrics] wrote: {events_jsonl}")
    print(f"[summarize_metrics] updated: {index_md}")


if __name__ == "__main__":
    main()
