#!/bin/bash
# ======================================================================
# Example RALPH mission config: manuscript reviewer response
#
# This config file is sourced by ralph.sh to configure a loop that
# addresses peer reviewer comments on a scientific manuscript.
#
# Usage:
#   bash ralph.sh all examples/manuscript_review_config.sh
# ======================================================================

# ── Loop identity ──
LOOP_NAME="ralph44"
BASELINE_TAG="ralph44-baseline"

# ── Project directory ──
PROJECT_DIR="/path/to/your/manuscript"

# ── Task assignments ──
# Analysis tasks run in parallel first (Phase B), writing tasks after (Phase C)
ANALYSIS_TASKS_STR="1 2 3 4"
WRITING_TASKS_STR="5 6 7 8"

# ── Iteration budget ──
# How many times to retry each task if the agent doesn't complete it
WORKER_ITER=3

# ── Agent configuration ──
AGENT_MODEL="claude-opus-4-6"
ALLOWED_TOOLS="Read,Edit,Write,Bash(tectonic:*),Bash(python3:*),Bash(git add:*),Bash(git commit:*),Bash(git status),Bash(git diff:*),Bash(git log:*),Bash(ls:*),Bash(wc:*),Bash(head:*),Bash(tail:*),Bash(mkdir:*),Bash(cp:*),Bash(mv:*),Bash(grep:*),Bash(chmod:*),Bash(find:*),Glob,Grep"

# ── File naming ──
PLAN_FILE="ralph44_plan.md"
ACTIVITY_FILE="ralph44_activity.md"
PROMPT_FILE="ralph44_PROMPT.md"
REVIEW_FILE="reviews_02MAY2026.txt"

# ── Context files injected into every task prompt ──
# These get @-referenced at the top of each task prompt
CONTEXT_FILES="${PROJECT_DIR}/CLAUDE.md"

# ── Verification commands (run in Phase E) ──
# Each line is a shell command that must exit 0
VERIFY_COMMANDS="tectonic main.tex
tectonic supplemental_information.tex"

# ── Custom task prompt body ──
# Override the default task prompt with manuscript-specific instructions.
# This function is called by ralph.sh when generating per-task prompts.
ralph_task_prompt_body() {
    local task_id="$1"
    local wt="$2"
    local branch="$3"

    cat <<BODYEOF

## Voice calibration (non-negotiable)

- Every claim gets a number (fold-changes, p-values, effect sizes)
- Active mechanistic verbs (encodes, enables, generates, reveals)
- No hedging (no "may suggest", "could potentially")
- Kill on sight: "delve", "leverage", "utilize", "facilitate"

## Tone (non-negotiable)

The manuscript is being improved, not defended. Never apologetic.
FORBIDDEN PHRASES: "acknowledge", "regret", "unfortunately", "caveat",
"we concede", "we admit", "limitation of our".

## Workflow

1. Read ${PLAN_FILE}; locate task ${task_id}. If \`passes\` is already
   true, output <promise>COMPLETE</promise> and stop.
2. Re-read the relevant reviewer concern in ${REVIEW_FILE}.
3. Execute the task per its description in the plan:
   - Analysis task: write & run a timestamped script in \`scripts/\`,
     write outputs to \`source_data/\` with a provenance header.
   - Writing task: edit main.tex and/or supplemental_information.tex
     using ONLY existing source_data numbers.
4. Intensifier audit: grep for forbidden intensifiers.
5. Compile: \`tectonic main.tex && tectonic supplemental_information.tex\`.
6. Set \`"passes": true\` for task ${task_id} in ${PLAN_FILE}.
7. Append a dated entry to ${ACTIVITY_FILE}:
     ## YYYY-MM-DD — Task ${task_id} complete
     - Reviewer concern: ...
     - Outputs: ...
     - Key numbers: ...
     - Manuscript edit summary: ...
8. Git commit ON THIS BRANCH (${branch}). Stage only files you touched.
9. Output <promise>COMPLETE</promise>.

## Data integrity

No synthetic data, no fabricated values, no placeholder numbers.
BODYEOF
}
