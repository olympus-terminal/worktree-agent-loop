#!/bin/bash
# ralph_resolve_conflicts.sh — auto-resolve merge conflicts via Claude
#
# For each task that failed to merge, re-attempt the merge and invoke
# Claude with a narrow prompt to resolve conflict markers (keep-both
# semantics for parallel edits to the same file).
#
# Environment variables (set by ralph.sh or caller):
#   LOOP_NAME    — loop identifier (default: ralph)
#   PLAN_FILE    — plan filename (default: ${LOOP_NAME}_plan.md)
#   AGENT_MODEL  — Claude model (default: claude-opus-4-6)
#
# Usage:
#   LOOP_NAME=ralph44 bash ralph_resolve_conflicts.sh

set -uo pipefail

LOOP_NAME="${LOOP_NAME:-ralph}"
PLAN_FILE="${PLAN_FILE:-${LOOP_NAME}_plan.md}"
AGENT_MODEL="${AGENT_MODEL:-claude-opus-4-6}"

LOG_DIR="${LOOP_NAME}_logs"
TS=$(date '+%Y%m%d_%H%M%S')
LOG="${LOG_DIR}/resolve_${TS}.log"
PENDING="${LOG_DIR}/pending_conflicts_latest.txt"

mkdir -p "$LOG_DIR"

if [ ! -f "$PENDING" ]; then
    echo "No pending-conflicts file at ${PENDING} — nothing to do."
    exit 0
fi

echo "========================================" | tee "$LOG"
echo "${LOOP_NAME} conflict resolver — ${TS}"   | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"

write_resolve_prompt() {
    local tid="$1"
    cat > /tmp/ralph_resolve_prompt.md <<PROMPTEOF
@${PLAN_FILE}

# Resolve merge conflicts for ${LOOP_NAME}/task${tid}

You are resolving a git merge conflict. The repository is mid-merge.
Some files contain \`<<<<<<< HEAD\`, \`=======\`,
\`>>>>>>> ${LOOP_NAME}/task${tid}\` conflict markers.

## Your job

1. Run \`git status\` to see unmerged paths.
2. For EACH unmerged file:
   - Read the file
   - Find all conflict regions
   - Resolve each by **keeping both contributions** — both sides were
     authored for different tasks. The correct resolution is almost
     always "both belong in the final text".
   - Where two sides edit the *same sentence* differently, prefer the
     version with more precise numerical statements.
   - Remove all \`<<<<<<<\`, \`=======\`, \`>>>>>>>\` markers.
3. Verify the result compiles/builds successfully.
4. Stage resolved files: \`git add <file>...\`
5. Complete the merge: \`git commit --no-edit\`
6. Output \`<promise>COMPLETE</promise>\`

## Guardrails

- Do NOT abort the merge.
- Do NOT edit files not listed as unmerged.
- Do NOT fabricate data. If unsure which side is correct, KEEP BOTH.
- Never use \`git merge --abort\` or \`git reset\`.
PROMPTEOF
}

FAIL=0
while IFS=: read -r tid _rest; do
    [ -z "$tid" ] && continue
    branch="${LOOP_NAME}/task${tid}"

    echo "" | tee -a "$LOG"
    echo "=== resolving ${branch} ===" | tee -a "$LOG"

    # Clean state
    if ! git diff --quiet HEAD 2>/dev/null; then
        git stash push -u -m "resolve stash ${TS}" 2>/dev/null || true
    fi
    if [ -f .git/MERGE_HEAD ]; then
        git merge --abort 2>/dev/null || true
    fi

    # Re-attempt merge
    echo "  starting merge" | tee -a "$LOG"
    git merge --no-ff --no-edit -m "Merge ${LOOP_NAME} task ${tid}" "${branch}" >> "$LOG" 2>&1 || true

    if [ ! -f .git/MERGE_HEAD ]; then
        echo "  [ok] merged without conflict" | tee -a "$LOG"
        continue
    fi

    conflicted=$(git diff --name-only --diff-filter=U 2>/dev/null)
    if [ -z "$conflicted" ]; then
        git commit --no-edit >> "$LOG" 2>&1
        echo "  [ok] finalized merge" | tee -a "$LOG"
        continue
    fi

    echo "  unmerged: ${conflicted}" | tee -a "$LOG"
    write_resolve_prompt "${tid}"

    result=$(claude --model "${AGENT_MODEL}" \
        --dangerously-skip-permissions \
        -p "$(cat /tmp/ralph_resolve_prompt.md)" \
        --output-format text \
        --allowedTools "Read,Edit,Write,Bash(git add:*),Bash(git commit:*),Bash(git status),Bash(git diff:*),Bash(ls:*),Glob,Grep" \
        2>&1) || true

    echo "$result" >> "$LOG"

    if [ -f .git/MERGE_HEAD ]; then
        echo "  [FAIL] merge still unfinished after Claude pass" | tee -a "$LOG"
        git merge --abort 2>/dev/null || true
        FAIL=$((FAIL+1))
    else
        echo "  [ok] merge finalized" | tee -a "$LOG"
    fi
done < "$PENDING"

echo "" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"
echo "Conflict resolver done. Failures: ${FAIL}" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"

exit ${FAIL}
