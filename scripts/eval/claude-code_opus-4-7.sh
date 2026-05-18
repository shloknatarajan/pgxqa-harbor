#!/usr/bin/env bash
# Sweep claude-code (claude-opus-4-7) across every dataset category.
source "$(dirname "$0")/_lib.sh"
run_eval claude-code claude-opus-4-7
