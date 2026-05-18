#!/usr/bin/env bash
# Sweep gemini-cli (gemini-2.5-flash) across every dataset category.
source "$(dirname "$0")/_lib.sh"
run_eval gemini-cli gemini-2.5-flash
