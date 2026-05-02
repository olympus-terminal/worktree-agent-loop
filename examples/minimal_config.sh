#!/bin/bash
# ======================================================================
# Minimal RALPH mission config
#
# The simplest possible config: a loop name, task arrays, and a
# verification command. Everything else uses defaults.
#
# Usage:
#   cd /path/to/your/project
#   bash /path/to/ralph.sh all /path/to/this/config.sh
# ======================================================================

LOOP_NAME="fix-batch"
PROJECT_DIR="$(pwd)"

# Two analysis tasks, one writing task
ANALYSIS_TASKS_STR="1 2"
WRITING_TASKS_STR="3"

# Files (must exist in PROJECT_DIR)
PLAN_FILE="fix-batch_plan.md"
ACTIVITY_FILE="fix-batch_activity.md"
PROMPT_FILE="fix-batch_PROMPT.md"

# Verify with pytest
VERIFY_COMMANDS="python3 -m pytest tests/ -q"
