#!/usr/bin/env bash
# Sweep claude-code (claude-sonnet-4-6) across every dataset category.
source "$(dirname "$0")/_lib.sh"
run_eval claude-code claude-sonnet-4-6
