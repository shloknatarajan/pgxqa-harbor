#!/usr/bin/env bash
# Sweep codex (gpt-5) across every dataset category.
# Override knobs: N_TRIALS=3 TASK_LIMIT=5 ./scripts/eval/codex_gpt-5.sh
source "$(dirname "$0")/_lib.sh"
run_eval codex gpt-5
