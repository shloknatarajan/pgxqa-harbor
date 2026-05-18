#!/usr/bin/env bash
# Sweep codex (o4-mini) across every dataset category.
source "$(dirname "$0")/_lib.sh"
run_eval codex o4-mini
