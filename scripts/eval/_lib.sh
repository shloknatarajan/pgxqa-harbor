# Shared helpers for evaluation sweep scripts.
# Source this from a per-(agent, model) sweep script.
#
# Exports:
#   DATASETS                  - bash array of dataset paths (all question categories)
#   N_TRIALS                  - default trials per task (override via env: N_TRIALS=3 ./script.sh)
#   TASK_LIMIT                - optional cap per dataset for smoke runs (env: TASK_LIMIT=5)
#   SKIP_IF_EXISTS            - if "1" (default), skip (agent, model, dataset) combos that already
#                               have a complete job in jobs/. Set to "0" to force re-run.
#   run_eval AGENT MODEL      - run AGENT/MODEL across every dataset in DATASETS

set -euo pipefail

# --- Activate project virtualenv if present -------------------------------
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${_lib_dir}/../.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ -f ".venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source ".venv/bin/activate"
fi

# --- Dataset list (categories included in the response matrix) ------------
# Scoped to the three Agent CLI datasets evaluated in the paper:
#   CPIC zero-context, CPIC evidence-provided, and cross-document summary QA.
# Chained questions are excluded for now (handled separately).
DATASETS=(
  "cpic_zero_context"
  "cpic_evidence_benchmark"
  "summary_qa"
)

# --- Knobs ----------------------------------------------------------------
N_TRIALS="${N_TRIALS:-1}"
TASK_LIMIT="${TASK_LIMIT:-}"
SKIP_IF_EXISTS="${SKIP_IF_EXISTS:-1}"

LOG_DIR="${PROJECT_ROOT}/run_results/sweep_logs"
mkdir -p "${LOG_DIR}"

# --- Helpers --------------------------------------------------------------

# Return 0 if a finished job already exists for (agent, model, dataset).
# Match is purely by config.json fields so it works across re-runs.
_has_existing_job() {
  local agent="$1" model="$2" dataset="$3"
  python - "$agent" "$model" "$dataset" <<'PY'
import json, sys
from pathlib import Path

agent, model, dataset = sys.argv[1], sys.argv[2], sys.argv[3]
jobs = Path("jobs")
if not jobs.exists():
    sys.exit(1)

for jd in jobs.iterdir():
    cfg_path = jd / "config.json"
    res_path = jd / "result.json"
    if not (cfg_path.exists() and res_path.exists()):
        continue
    try:
        cfg = json.loads(cfg_path.read_text())
    except Exception:
        continue
    agents = cfg.get("agents") or []
    datasets = cfg.get("datasets") or []
    if not agents or not datasets:
        continue
    a = agents[0]
    d = datasets[0]
    if (a.get("name") == agent
        and (a.get("model_name") or "") == (model or "")
        and Path(d.get("path", "")).name == Path(dataset).name):
        sys.exit(0)
sys.exit(1)
PY
}

# run_eval AGENT MODEL
#   Sweeps every dataset in DATASETS for the given agent/model pair.
run_eval() {
  local agent="$1"
  local model="${2:-}"
  local tag="${agent}__${model:-default}"
  local total="${#DATASETS[@]}"
  local i=0

  echo
  echo "##########################################################"
  echo "# Sweep: agent=${agent}  model=${model:-<default>}"
  echo "# Datasets: ${total}   trials/task: ${N_TRIALS}   limit/dataset: ${TASK_LIMIT:-all}"
  echo "##########################################################"

  for ds in "${DATASETS[@]}"; do
    i=$((i + 1))
    echo
    echo "--- (${i}/${total}) ${tag} :: ${ds} ---"

    if [[ "${SKIP_IF_EXISTS}" == "1" ]] && _has_existing_job "${agent}" "${model}" "${ds}"; then
      echo "  [skip] existing job found for (${agent}, ${model:-<default>}, ${ds}). Set SKIP_IF_EXISTS=0 to force."
      continue
    fi

    local args=(-p "${ds}" -a "${agent}" -n "${N_TRIALS}")
    if [[ -n "${model}" ]]; then
      args+=(-m "${model}")
    fi
    if [[ -n "${TASK_LIMIT}" ]]; then
      args+=(-l "${TASK_LIMIT}")
    fi

    local logfile="${LOG_DIR}/${tag}__${ds}.log"
    echo "  cmd: python main.py ${args[*]}"
    echo "  log: ${logfile}"

    # Tee to log file; don't let one dataset failure kill the whole sweep.
    if ! python main.py "${args[@]}" 2>&1 | tee "${logfile}"; then
      echo "  [warn] non-zero exit for ${ds}; continuing sweep."
    fi
  done

  echo
  echo "Sweep done for ${tag}."
}
