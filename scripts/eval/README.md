# Eval Sweep Scripts

Goal: run every dataset category (= "all questions as a whole") on each
(agent, model) combination and end up with a model × task **response matrix**.

## Layout

```
scripts/
├── eval/
│   ├── _lib.sh                       # shared helpers (DATASETS list + run_eval)
│   ├── run_all.sh                    # master: runs every *.sh in this dir
│   ├── codex_gpt-5.sh                # one sweep per (agent, model)
│   ├── codex_gpt-5.2.sh
│   ├── codex_o4-mini.sh
│   ├── claude-code_opus-4-7.sh
│   ├── claude-code_sonnet-4-6.sh
│   ├── claude-code_haiku-4-5.sh
│   ├── gemini-cli_2.5-pro.sh
│   └── gemini-cli_2.5-flash.sh
└── build_matrix.py                   # aggregate jobs/* into the response matrix
```

Each per-(agent, model) script sweeps these dataset "categories"
(matches the Agent CLI tier evaluated in the paper, chained questions
excluded):

- `cpic_zero_context` — 100 tasks
- `cpic_evidence_benchmark` — 106 tasks
- `summary_qa` — 100 tasks

**Total: 306 tasks per sweep.**

(edit the `DATASETS` array in `_lib.sh` to add/remove categories)

## Run one (agent, model) sweep

```bash
./scripts/eval/codex_gpt-5.sh                     # full sweep, n=1 per task
N_TRIALS=2 ./scripts/eval/codex_gpt-5.sh          # 2 trials per task
TASK_LIMIT=5 ./scripts/eval/codex_gpt-5.sh        # smoke test (5 tasks/dataset)
SKIP_IF_EXISTS=0 ./scripts/eval/codex_gpt-5.sh    # force re-run even if jobs exist
```

## Run everything

```bash
./scripts/eval/run_all.sh                                 # all (agent, model) sweeps
ONLY="codex_gpt-5 claude-code_opus-4-7" ./scripts/eval/run_all.sh   # subset
N_TRIALS=2 TASK_LIMIT=3 ./scripts/eval/run_all.sh         # quick e2e validation
```

Per-sweep stdout is also tee'd into `run_results/sweep_logs/<agent>__<model>__<dataset>.log`.

## Data flow / where results live

`main.py` already saves into:

- `jobs/<timestamp>/` — raw per-trial output (`config.json`, `result.json`, per-trial subdirs)
- `run_results/<timestamp>_<dataset>.txt` — human-readable per-job summary

These scripts don't change that. The matrix is built from `jobs/*` post hoc, so
nothing is lost if a sweep is interrupted — re-running with default
`SKIP_IF_EXISTS=1` picks up where you left off (matching on agent + model +
dataset in each job's `config.json`).

## Build the response matrix

```bash
python scripts/build_matrix.py                       # all jobs
python scripts/build_matrix.py --since 2026-05       # only jobs dated 2026-05*
python scripts/build_matrix.py --out run_results/matrix_v2
```

Produces, in `run_results/matrix/`:

- `long.csv` — one row per (job, agent, model, dataset, task, trial)
- `matrix_reward.csv` — rows = `dataset/task`, cols = `agent::model`, value = mean reward
- `matrix_pass.csv` — same shape, `1` if any trial passed, `0` if it ran and failed, blank if not attempted
- `matrix.json` — machine-readable view of the above plus trial counts

## Adding a new (agent, model)

Drop a new file `scripts/eval/<agent>_<model>.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"
run_eval <agent> <model>
```

`run_all.sh` picks it up automatically.

## Adding a new dataset category

Add the path to the `DATASETS` array in `scripts/eval/_lib.sh`. All
existing sweeps will start covering it on the next run.
