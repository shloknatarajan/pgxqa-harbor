#!/usr/bin/env bash
# Sweep codex (gpt-5.2) across every dataset category.
source "$(dirname "$0")/_lib.sh"
run_eval codex gpt-5.5
