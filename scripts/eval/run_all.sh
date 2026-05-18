#!/usr/bin/env bash
# Master runner: invoke every per-(agent, model) sweep script in this directory.
#
# Usage:
#   ./scripts/eval/run_all.sh                  # run everything; skip combos already in jobs/
#   N_TRIALS=2 ./scripts/eval/run_all.sh       # 2 trials per task
#   TASK_LIMIT=5 ./scripts/eval/run_all.sh     # smoke test (5 tasks per dataset)
#   SKIP_IF_EXISTS=0 ./scripts/eval/run_all.sh # force re-run even if results exist
#   ONLY="codex_gpt-5 claude-code_opus-4-7" ./scripts/eval/run_all.sh   # subset

set -uo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"

# Collect candidate scripts (everything ending in .sh that isn't this one or _lib.sh).
mapfile -t scripts < <(find "${dir}" -maxdepth 1 -type f -name "*.sh" \
  ! -name "_lib.sh" ! -name "run_all.sh" | sort)

# Optional ONLY filter (space-separated stems).
if [[ -n "${ONLY:-}" ]]; then
  filtered=()
  for s in "${scripts[@]}"; do
    stem="$(basename "${s}" .sh)"
    for want in ${ONLY}; do
      if [[ "${stem}" == "${want}" ]]; then
        filtered+=("${s}")
        break
      fi
    done
  done
  scripts=("${filtered[@]}")
fi

if [[ ${#scripts[@]} -eq 0 ]]; then
  echo "No sweep scripts found in ${dir}"
  exit 1
fi

echo "Will run ${#scripts[@]} sweep script(s):"
for s in "${scripts[@]}"; do echo "  - $(basename "${s}")"; done
echo

failed=()
for s in "${scripts[@]}"; do
  echo
  echo "============================================================"
  echo "== Starting $(basename "${s}")"
  echo "============================================================"
  if ! bash "${s}"; then
    echo "[run_all] $(basename "${s}") returned non-zero; continuing."
    failed+=("$(basename "${s}")")
  fi
done

echo
echo "============================================================"
echo "All sweeps complete."
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Sweeps with non-zero exit:"
  for f in "${failed[@]}"; do echo "  - ${f}"; done
fi
echo
echo "Build the response matrix with:"
echo "  python scripts/build_matrix.py"
