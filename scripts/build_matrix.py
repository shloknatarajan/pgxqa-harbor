"""Build a model x task response matrix from all completed jobs in jobs/.

Walks every jobs/<timestamp>/ directory, reads config.json to find
(agent, model, dataset), then for each trial subdir reads result.json to
extract (task_name, reward, status). Joins everything into a long-form
DataFrame and pivots into a matrix.

Outputs (under run_results/matrix/):
  - long.csv             one row per (agent, model, dataset, task, trial)
  - matrix_reward.csv    rows=task (dataset/task), cols=agent::model, value=mean reward
  - matrix_pass.csv      same shape, value in {1, 0, NaN} (pass/fail/missing)
  - matrix.json          machine-readable nested dict

Usage:
  python scripts/build_matrix.py                 # all jobs
  python scripts/build_matrix.py --since 2026-05 # only jobs whose dirname starts with this
  python scripts/build_matrix.py --jobs-dir jobs --out run_results/matrix
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path
from statistics import mean


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def trial_reward(result: dict) -> float | None:
    vr = result.get("verifier_result") or {}
    rewards = vr.get("rewards") or {}
    r = rewards.get("reward")
    if r is None:
        return None
    try:
        return float(r)
    except (TypeError, ValueError):
        return None


def trial_status(result: dict, reward: float | None) -> str:
    if result.get("exception_info"):
        return "error"
    if reward is None:
        return "unknown"
    if reward >= 1.0:
        return "pass"
    if reward > 0:
        return "partial"
    return "fail"


def collect_rows(jobs_dir: Path, since: str | None) -> list[dict]:
    rows: list[dict] = []
    if not jobs_dir.exists():
        return rows
    for job_dir in sorted(p for p in jobs_dir.iterdir() if p.is_dir()):
        if since and not job_dir.name.startswith(since):
            continue
        config = load_json(job_dir / "config.json")
        if not config:
            continue
        agents = config.get("agents") or []
        datasets = config.get("datasets") or []
        if not agents or not datasets:
            continue
        agent_name = agents[0].get("name") or ""
        model_name = agents[0].get("model_name") or ""
        dataset_path = datasets[0].get("path") or ""
        dataset = Path(dataset_path).name or dataset_path

        for trial_dir in sorted(p for p in job_dir.iterdir() if p.is_dir()):
            result = load_json(trial_dir / "result.json")
            if not result:
                continue
            task_name = result.get("task_name") or trial_dir.name
            reward = trial_reward(result)
            status = trial_status(result, reward)
            rows.append({
                "job": job_dir.name,
                "agent": agent_name,
                "model": model_name,
                "dataset": dataset,
                "task": task_name,
                "trial_dir": trial_dir.name,
                "reward": reward if reward is not None else "",
                "status": status,
            })
    return rows


def write_long(rows: list[dict], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["job", "agent", "model", "dataset", "task", "trial_dir", "reward", "status"]
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def _model_key(agent: str, model: str) -> str:
    return f"{agent}::{model or '<default>'}"


def build_matrix(rows: list[dict]):
    """Aggregate trials by (dataset, task) x (agent, model).

    Returns:
      tasks      sorted list of "dataset/task" row keys
      models     sorted list of "agent::model" column keys
      reward     dict[task_row][model_col] = mean reward (or None)
      passed     dict[task_row][model_col] = 1.0 if any trial passed, 0.0 if any trial ran, None otherwise
      trials     dict[task_row][model_col] = number of trials seen
    """
    cells = defaultdict(lambda: defaultdict(list))   # rewards per (task_row, model_col)
    pass_cells = defaultdict(lambda: defaultdict(list))  # 1/0 per trial
    for r in rows:
        task_row = f"{r['dataset']}/{r['task']}"
        model_col = _model_key(r["agent"], r["model"])
        rw = r["reward"]
        if rw != "" and rw is not None:
            cells[task_row][model_col].append(float(rw))
            pass_cells[task_row][model_col].append(1.0 if float(rw) >= 1.0 else 0.0)
        else:
            # still record the attempt as a 0 so we know it ran
            pass_cells[task_row][model_col].append(0.0)

    tasks = sorted(cells.keys() | pass_cells.keys())
    models = sorted({m for row in pass_cells.values() for m in row.keys()})

    reward = {t: {} for t in tasks}
    passed = {t: {} for t in tasks}
    trials = {t: {} for t in tasks}
    for t in tasks:
        for m in models:
            rws = cells.get(t, {}).get(m, [])
            ps = pass_cells.get(t, {}).get(m, [])
            reward[t][m] = mean(rws) if rws else None
            passed[t][m] = (1.0 if any(p >= 1.0 for p in ps) else 0.0) if ps else None
            trials[t][m] = len(ps)
    return tasks, models, reward, passed, trials


def write_matrix_csv(tasks, models, values, path: Path, fmt=lambda v: "" if v is None else f"{v:.4g}"):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["task", *models])
        for t in tasks:
            w.writerow([t, *(fmt(values[t][m]) for m in models)])


def write_matrix_json(tasks, models, reward, passed, trials, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "tasks": tasks,
        "models": models,
        "reward": reward,
        "pass": passed,
        "trials": trials,
    }
    path.write_text(json.dumps(payload, indent=2, default=str))


def print_summary(tasks, models, passed, trials):
    print(f"\nMatrix: {len(tasks)} tasks x {len(models)} model columns")
    if not models:
        print("  (no model columns found — run some sweeps first)")
        return
    width = max(len(m) for m in models)
    print("\nPer-model coverage / pass rate:")
    print(f"  {'model':<{width}}  tasks_covered  passes  pass_rate")
    for m in models:
        covered = sum(1 for t in tasks if trials[t][m])
        passes = sum(1 for t in tasks if (passed[t][m] or 0) >= 1.0)
        rate = (passes / covered) if covered else 0.0
        print(f"  {m:<{width}}  {covered:>13}  {passes:>6}  {rate:>8.1%}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs-dir", default="jobs", help="Directory holding job folders")
    ap.add_argument("--out", default="run_results/matrix", help="Output directory")
    ap.add_argument("--since", default=None, help="Only include jobs whose dirname starts with this string")
    args = ap.parse_args()

    jobs_dir = Path(args.jobs_dir)
    out_dir = Path(args.out)

    rows = collect_rows(jobs_dir, args.since)
    if not rows:
        print(f"No trial results found under {jobs_dir}/")
        return

    write_long(rows, out_dir / "long.csv")
    print(f"  wrote {out_dir / 'long.csv'}  ({len(rows)} trial rows)")

    tasks, models, reward, passed, trials = build_matrix(rows)
    write_matrix_csv(tasks, models, reward, out_dir / "matrix_reward.csv")
    write_matrix_csv(tasks, models, passed, out_dir / "matrix_pass.csv",
                     fmt=lambda v: "" if v is None else ("1" if v >= 1.0 else "0"))
    write_matrix_json(tasks, models, reward, passed, trials, out_dir / "matrix.json")
    print(f"  wrote {out_dir / 'matrix_reward.csv'}")
    print(f"  wrote {out_dir / 'matrix_pass.csv'}")
    print(f"  wrote {out_dir / 'matrix.json'}")

    print_summary(tasks, models, passed, trials)


if __name__ == "__main__":
    main()
