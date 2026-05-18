#!/usr/bin/env bash
# Sweep claude-code (claude-haiku-4-5) across every dataset category.
source "$(dirname "$0")/_lib.sh"
run_eval claude-code claude-haiku-4-5
