#!/bin/bash
# ======================================================================
# ralph.sh — parallel Claude Code agents in isolated git worktrees
#
# A framework for running parallel Claude Code agents in isolated git
# worktrees, each executing one task from a JSON plan, then merging
# results back into the main branch with full revertability.
#
# ARCHITECTURE
#   Phase A (sequential, main worktree):   preflight checks, baseline tag
#   Phase B (parallel, isolated worktrees): analysis tasks
#   Phase C (parallel, isolated worktrees): writing tasks
#   Phase D (sequential, main worktree):   merge worker branches into main
#   Phase E (sequential, main worktree):   final verification
#
# REVERTABILITY
#   A baseline git tag is created at HEAD before any edits. Each task
#   lives on its own sub-branch and is merged via `git merge --no-ff`,
#   so `git revert <merge-sha>` cleanly undoes one task.
#
# USAGE
#   1. Copy ralph.sh, ralph_merge_drivers.sh, ralph_resolve_conflicts.sh
#      into your project.
#   2. Create a mission config (see examples/mission_config.sh).
#   3. Create a plan.md (JSON array), prompt.md, and activity.md.
#   4. Run:  bash ralph.sh [phase] [config]
#
#   Phases: all (default), preflight, analysis, writing, integrate,
#           verify, continue (skip preflight)
#
# EXIT CODES
#   0   clean completion (or partial with warnings)
#   1   preflight failure
#   130 user interrupt (Ctrl-C)
# ======================================================================

set -uo pipefail
trap 'echo ""; echo "Interrupted by user." | tee -a "${LOG_FILE:-/dev/null}"; exit 130' INT TERM

# ======================================================================
# CONFIGURATION — override via mission config file
# ======================================================================

# Loop identity
LOOP_NAME="${LOOP_NAME:-ralph}"
BASELINE_TAG="${BASELINE_TAG:-${LOOP_NAME}-baseline}"

# Working directory (project root)
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

# Task assignments (space-separated IDs)
ANALYSIS_TASKS=(${ANALYSIS_TASKS_STR:-})
WRITING_TASKS=(${WRITING_TASKS_STR:-})

# Iteration budgets
WORKER_ITER="${WORKER_ITER:-3}"

# Agent configuration
AGENT_MODEL="${AGENT_MODEL:-claude-opus-4-6}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Read,Edit,Write,Bash(tectonic:*),Bash(python3:*),Bash(git add:*),Bash(git commit:*),Bash(git status),Bash(git diff:*),Bash(git log:*),Bash(ls:*),Bash(wc:*),Bash(head:*),Bash(tail:*),Bash(mkdir:*),Bash(cp:*),Bash(mv:*),Bash(grep:*),Bash(chmod:*),Bash(find:*),Glob,Grep}"

# File naming
PLAN_FILE="${PLAN_FILE:-${LOOP_NAME}_plan.md}"
ACTIVITY_FILE="${ACTIVITY_FILE:-${LOOP_NAME}_activity.md}"
PROMPT_FILE="${PROMPT_FILE:-${LOOP_NAME}_PROMPT.md}"
REVIEW_FILE="${REVIEW_FILE:-}"

# Verification commands (newline-separated; each must exit 0)
VERIFY_COMMANDS="${VERIFY_COMMANDS:-}"

# Context files to inject into task prompts (space-separated paths)
CONTEXT_FILES="${CONTEXT_FILES:-}"

# Extra files to copy into each worktree (space-separated, relative to PROJECT_DIR)
# Use for untracked files the agent needs (PRD, reference data, etc.)
EXTRA_COPY_FILES="${EXTRA_COPY_FILES:-}"

# Extra directories to create in each worktree (space-separated, relative)
EXTRA_MKDIRS="${EXTRA_MKDIRS:-}"

# ======================================================================
# Load mission config if provided
# ======================================================================
PHASE=${1:-all}
CONFIG_FILE=${2:-""}

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    # Re-parse task arrays after sourcing config
    ANALYSIS_TASKS=(${ANALYSIS_TASKS_STR:-})
    WRITING_TASKS=(${WRITING_TASKS_STR:-})
fi

# Derived paths
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_DIR="${PROJECT_DIR}/${LOOP_NAME}_logs"
LOG_FILE="${LOG_DIR}/${LOOP_NAME}_main_${TIMESTAMP}.log"
WT_BASE="${PROJECT_DIR}/.wt_${LOOP_NAME}"

cd "$PROJECT_DIR"
mkdir -p "$LOG_DIR"

echo "========================================" | tee "$LOG_FILE"
echo "RALPH: ${LOOP_NAME}"                      | tee -a "$LOG_FILE"
echo "Phase:   $PHASE"                          | tee -a "$LOG_FILE"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"    | tee -a "$LOG_FILE"
echo "Tasks:   analysis=[${ANALYSIS_TASKS[*]:-}] writing=[${WRITING_TASKS[*]:-}]" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# ======================================================================
# PHASE A — Preflight
# ======================================================================
run_preflight() {
    echo "" | tee -a "$LOG_FILE"
    echo "=== PHASE A: Preflight ===" | tee -a "$LOG_FILE"

    # Check required files
    local required_files=("$PLAN_FILE" "$ACTIVITY_FILE" "$PROMPT_FILE")
    [ -n "$REVIEW_FILE" ] && required_files+=("$REVIEW_FILE")

    for f in "${required_files[@]}"; do
        if [ ! -f "$f" ]; then
            echo "[FAIL] Required file not found: $f" | tee -a "$LOG_FILE"
            exit 1
        fi
    done
    echo "[OK] required files present" | tee -a "$LOG_FILE"

    # Baseline tag (idempotent)
    if ! git rev-parse "$BASELINE_TAG" >/dev/null 2>&1; then
        git tag "$BASELINE_TAG" HEAD
        echo "[TAG] Created $BASELINE_TAG at $(git rev-parse --short $BASELINE_TAG)" | tee -a "$LOG_FILE"
    else
        echo "[TAG] $BASELINE_TAG already at $(git rev-parse --short $BASELINE_TAG)" | tee -a "$LOG_FILE"
    fi

    # Clean tree warning
    if ! git diff --quiet HEAD 2>/dev/null; then
        echo "[WARN] working tree has uncommitted changes — worktrees branch from HEAD" | tee -a "$LOG_FILE"
    fi

    echo "Branch: $(git branch --show-current)" | tee -a "$LOG_FILE"
    echo "HEAD:   $(git log --oneline -1)"      | tee -a "$LOG_FILE"
}

# ======================================================================
# Helper: check if a task has passes:true in a plan file
# ======================================================================
task_complete() {
    local task_id="$1"
    local plan_file="${2:-$PLAN_FILE}"

    python3 - "$task_id" "$plan_file" <<'PYEOF' 2>/dev/null
import json, sys
task_id = int(sys.argv[1])
plan_path = sys.argv[2]
try:
    with open(plan_path) as f:
        tasks = json.load(f)
except Exception:
    sys.exit(2)
for t in tasks:
    if int(t.get("id", -1)) == task_id:
        sys.exit(0 if t.get("passes", False) else 1)
sys.exit(2)
PYEOF
}

# ======================================================================
# Helper: merge worker plan passes-state back into main plan
# ======================================================================
merge_worker_plan() {
    local worker_plan="$1"
    local main_plan="$2"
    local task_id="$3"

    if [[ ! -f "$worker_plan" ]]; then
        echo "[WARN] merge_worker_plan: worker plan missing: $worker_plan" | tee -a "$LOG_FILE"
        return 1
    fi

    python3 - "$worker_plan" "$main_plan" "$task_id" <<'PYEOF'
import json, sys
worker_path, main_path, task_id = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(worker_path) as f:
    worker = json.load(f)
with open(main_path) as f:
    main = json.load(f)
worker_task = next((t for t in worker if int(t.get("id", -1)) == task_id), None)
if worker_task is None:
    print(f"[merge] task {task_id}: not found in worker plan")
    sys.exit(0)
for i, t in enumerate(main):
    if int(t.get("id", -1)) == task_id:
        for key in ("passes", "notes"):
            if key in worker_task and main[i].get(key) != worker_task[key]:
                main[i][key] = worker_task[key]
        print(f"[merge] task {task_id}: passes={main[i].get('passes')}")
        break
with open(main_path, "w") as f:
    json.dump(main, f, indent=2)
PYEOF
}

# ======================================================================
# Helper: append worker activity entries into main activity log
# ======================================================================
merge_worker_activity() {
    local worker_activity="$1"
    local main_activity="${2:-$ACTIVITY_FILE}"
    [[ -f "$worker_activity" ]] || return 0

    python3 - "$worker_activity" "$main_activity" <<'PYEOF' 2>/dev/null || true
import sys, re
worker_path, main_path = sys.argv[1], sys.argv[2]
with open(worker_path) as f:
    worker_text = f.read()
try:
    with open(main_path) as f:
        main_text = f.read()
except FileNotFoundError:
    main_text = ""
entries = re.findall(r"## \d{4}-\d{2}-\d{2} — Task \d+ complete.*?(?=\n## |\Z)",
                     worker_text, re.DOTALL)
appended = 0
for e in entries:
    e = e.rstrip()
    if e and e not in main_text and len(e) > 40:
        with open(main_path, "a") as f:
            f.write("\n" + e + "\n")
        appended += 1
print(f"[activity] appended {appended} new entries")
PYEOF
}

# ======================================================================
# Set up a worktree for a single task
# ======================================================================
setup_task_worktree() {
    local task_id="$1"
    local branch="${LOOP_NAME}/task${task_id}"
    local wt="${WT_BASE}/task${task_id}"

    # Remove stale worktree
    if git worktree list --porcelain | grep -q "worktree ${wt}$"; then
        git worktree remove --force "${wt}" 2>/dev/null || true
    fi
    [ -d "${wt}" ] && rm -rf "${wt}"

    # Create branch off baseline if absent; otherwise reuse
    if ! git rev-parse --verify "${branch}" >/dev/null 2>&1; then
        git branch "${branch}" "${BASELINE_TAG}"
    fi
    git worktree add "${wt}" "${branch}" >/dev/null

    # Copy plan state into worktree
    cp "${PROJECT_DIR}/${PLAN_FILE}"     "${wt}/${PLAN_FILE}"
    cp "${PROJECT_DIR}/${ACTIVITY_FILE}" "${wt}/${ACTIVITY_FILE}"
    cp "${PROJECT_DIR}/${PROMPT_FILE}"   "${wt}/${PROMPT_FILE}"

    # Copy extra files (PRD, reference data, etc.)
    for extra in ${EXTRA_COPY_FILES}; do
        if [ -f "${PROJECT_DIR}/${extra}" ]; then
            cp "${PROJECT_DIR}/${extra}" "${wt}/${extra}"
        fi
    done

    # Create extra directories
    for d in ${EXTRA_MKDIRS}; do
        mkdir -p "${wt}/${d}"
    done

    # Build the task-scoped prompt
    local task_prompt="${wt}/${LOOP_NAME}_TASK_PROMPT.md"

    {
        # Context file references
        for ctx in ${CONTEXT_FILES}; do
            echo "@${ctx}"
        done
        echo "@${PLAN_FILE}"
        echo "@${ACTIVITY_FILE}"
        [ -n "$REVIEW_FILE" ] && echo "@${PROJECT_DIR}/${REVIEW_FILE}"
        echo ""

        echo "# ${LOOP_NAME} — Task ${task_id} (isolated worktree)"
        echo ""
        echo "You are running in an ISOLATED GIT WORKTREE for ${LOOP_NAME} task ${task_id}"
        echo "ONLY. Do NOT work on any other task. If task ${task_id} already has"
        echo "\`\"passes\": true\` in ${PLAN_FILE}, immediately output"
        echo "<promise>COMPLETE</promise> and do nothing else."
        echo ""
        echo "You are on branch: ${branch}"
        echo "Working directory: ${wt}"
        echo ""

        # Inject custom task prompt content if the mission provides it
        if type -t ralph_task_prompt_body >/dev/null 2>&1; then
            ralph_task_prompt_body "${task_id}" "${wt}" "${branch}"
        else
            # Default task prompt body
            cat <<DEFAULTEOF

## Workflow

1. Read ${PLAN_FILE}; locate task ${task_id}. If \`passes\` is already
   true, output <promise>COMPLETE</promise> and stop.
2. Execute the task per its description in the plan.
3. Compile/verify outputs per the project's requirements.
4. Set \`"passes": true\` for task ${task_id} in ${PLAN_FILE}.
5. Append a dated entry to ${ACTIVITY_FILE}:
     ## YYYY-MM-DD — Task ${task_id} complete
     - Outputs: [files created/modified]
     - Summary: [one sentence]
6. Git commit ON THIS BRANCH (${branch}). Stage only files
   you touched. Commit message from the task description.
7. Output <promise>COMPLETE</promise>.

## Data integrity

No synthetic data, no fabricated values, no placeholder numbers. If a
required input file is missing, STOP and report — do not invent.
DEFAULTEOF
        fi
    } > "${task_prompt}"

    echo "${wt}"
}

# ======================================================================
# Run a single-task worker in its worktree
# ======================================================================
run_task_worker() {
    local task_id="$1"
    local wt="$2"
    local log="${LOG_DIR}/task${task_id}_${TIMESTAMP}.log"

    echo "=== task ${task_id} START — $(date '+%Y-%m-%d %H:%M:%S') ===" > "$log"
    echo "Worktree: ${wt}" >> "$log"
    echo "Branch:   ${LOOP_NAME}/task${task_id}" >> "$log"

    if task_complete "${task_id}" "${wt}/${PLAN_FILE}"; then
        echo "task ${task_id} already complete — skipping" | tee -a "$log"
        return 0
    fi

    cd "${wt}"

    for ((j=1; j<=WORKER_ITER; j++)); do
        echo "--- task ${task_id} iter ${j}/${WORKER_ITER} — $(date '+%H:%M:%S') ---" | tee -a "$log"

        result=$(claude --model "${AGENT_MODEL}" \
            --dangerously-skip-permissions \
            -p "$(cat ${LOOP_NAME}_TASK_PROMPT.md)" \
            --output-format text \
            --allowedTools "${ALLOWED_TOOLS}" \
            2>&1) || true

        echo "$result" >> "$log"

        if task_complete "${task_id}" "${PLAN_FILE}"; then
            echo "=== task ${task_id} COMPLETE after ${j} iter(s) ===" | tee -a "$log"
            cd "${PROJECT_DIR}"
            return 0
        fi

        if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
            if task_complete "${task_id}" "${PLAN_FILE}"; then
                echo "=== task ${task_id} COMPLETE (agent signal) ===" | tee -a "$log"
                cd "${PROJECT_DIR}"
                return 0
            fi
            echo "[NOTE] agent emitted COMPLETE but plan shows passes:false; continuing" | tee -a "$log"
        fi

        sleep 2
    done

    echo "[WARN] task ${task_id} did not complete in ${WORKER_ITER} iterations" | tee -a "$log"
    cd "${PROJECT_DIR}"
    return 1
}

# ======================================================================
# Run a batch of tasks in parallel worktrees
# ======================================================================
run_parallel_batch() {
    local phase_name="$1"
    shift
    local task_ids=("$@")

    if [ ${#task_ids[@]} -eq 0 ]; then
        echo "  ${phase_name}: no tasks assigned — skipping" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "" | tee -a "$LOG_FILE"
    echo "=== ${phase_name}: tasks ${task_ids[*]} ===" | tee -a "$LOG_FILE"

    local pending=()
    for tid in "${task_ids[@]}"; do
        if task_complete "$tid" "$PLAN_FILE"; then
            echo "  task ${tid}: already passes — skipping" | tee -a "$LOG_FILE"
        else
            pending+=("$tid")
        fi
    done

    if [ ${#pending[@]} -eq 0 ]; then
        echo "=== ${phase_name}: all tasks already complete ===" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "  pending: ${pending[*]}" | tee -a "$LOG_FILE"
    echo "  setting up worktrees..." | tee -a "$LOG_FILE"

    declare -A TASK_WT
    for tid in "${pending[@]}"; do
        wt=$(setup_task_worktree "$tid")
        TASK_WT[$tid]="$wt"
        echo "    task ${tid}: ${wt} [branch ${LOOP_NAME}/task${tid}]" | tee -a "$LOG_FILE"
    done

    echo "" | tee -a "$LOG_FILE"
    echo "Launching ${#pending[@]} parallel workers..." | tee -a "$LOG_FILE"

    declare -A PID_TASK
    for tid in "${pending[@]}"; do
        wt="${TASK_WT[$tid]}"
        (run_task_worker "$tid" "$wt") &
        PID_TASK[$!]=$tid
        echo "  task ${tid}: PID $!" | tee -a "$LOG_FILE"
    done

    echo "" | tee -a "$LOG_FILE"
    echo "Waiting for ${phase_name} workers..." | tee -a "$LOG_FILE"
    local fail=0
    for pid in "${!PID_TASK[@]}"; do
        if ! wait "$pid"; then
            echo "[WARN] task ${PID_TASK[$pid]} (pid $pid) exited non-zero" | tee -a "$LOG_FILE"
            fail=$((fail+1))
        fi
    done

    echo "${phase_name}: ${#pending[@]} task(s) attempted, ${fail} failed" | tee -a "$LOG_FILE"
}

# ======================================================================
# PHASE B — Analysis tasks in parallel
# ======================================================================
run_analysis_phase() {
    run_parallel_batch "PHASE B (Analysis)" "${ANALYSIS_TASKS[@]}"
}

# ======================================================================
# PHASE C — Writing tasks in parallel
# ======================================================================
run_writing_phase() {
    run_parallel_batch "PHASE C (Writing)" "${WRITING_TASKS[@]}"
}

# ======================================================================
# PHASE D — Integration: merge worker branches into main
# ======================================================================
run_integrate() {
    echo "" | tee -a "$LOG_FILE"
    echo "=== PHASE D: Integration (sequential merges into main) ===" | tee -a "$LOG_FILE"

    cd "${PROJECT_DIR}"

    # Install merge drivers if available
    local driver_script="${PROJECT_DIR}/ralph_merge_drivers.sh"
    if [ -f "$driver_script" ]; then
        LOOP_NAME="$LOOP_NAME" PLAN_FILE="$PLAN_FILE" ACTIVITY_FILE="$ACTIVITY_FILE" \
            bash "$driver_script" >> "$LOG_FILE" 2>&1 || true
    fi

    # Merge order: analysis first, then writing
    local merge_order=("${ANALYSIS_TASKS[@]}" "${WRITING_TASKS[@]}")
    local conflicts=()

    for tid in "${merge_order[@]}"; do
        local branch="${LOOP_NAME}/task${tid}"

        if ! git rev-parse --verify "${branch}" >/dev/null 2>&1; then
            echo "  task ${tid}: no branch — skipping" | tee -a "$LOG_FILE"
            continue
        fi

        local unique_commits
        unique_commits=$(git rev-list --count "$(git branch --show-current)..${branch}" 2>/dev/null || echo 0)
        if [ "$unique_commits" -eq 0 ]; then
            echo "  task ${tid}: no new commits — skipping" | tee -a "$LOG_FILE"
            continue
        fi

        echo "  task ${tid}: merging ${branch} (${unique_commits} commit[s])" | tee -a "$LOG_FILE"
        if git merge --no-ff --no-edit -m "Merge ${LOOP_NAME} task ${tid}" "${branch}" >> "$LOG_FILE" 2>&1 \
            && ! git diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
            echo "    merged cleanly." | tee -a "$LOG_FILE"

            # Sync plan + activity state
            local wt="${WT_BASE}/task${tid}"
            if [ -f "${wt}/${PLAN_FILE}" ]; then
                merge_worker_plan "${wt}/${PLAN_FILE}" "$PLAN_FILE" "$tid" 2>&1 | tee -a "$LOG_FILE"
            fi
            if [ -f "${wt}/${ACTIVITY_FILE}" ]; then
                merge_worker_activity "${wt}/${ACTIVITY_FILE}" "$ACTIVITY_FILE" 2>&1 | tee -a "$LOG_FILE"
            fi
        else
            local unmerged
            unmerged=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',')
            echo "[CONFLICT] task ${tid}: unmerged paths: ${unmerged}" | tee -a "$LOG_FILE"
            conflicts+=("${tid}:${unmerged}")
            git merge --abort 2>/dev/null || true
        fi
    done

    if [ ${#conflicts[@]} -gt 0 ]; then
        local pending="${LOG_DIR}/pending_conflicts_${TIMESTAMP}.txt"
        printf "%s\n" "${conflicts[@]}" > "$pending"
        cp "$pending" "${LOG_DIR}/pending_conflicts_latest.txt"
        echo "" | tee -a "$LOG_FILE"

        local resolver="${PROJECT_DIR}/ralph_resolve_conflicts.sh"
        if [ -f "$resolver" ]; then
            echo "Invoking conflict resolver for ${#conflicts[@]} task(s)..." | tee -a "$LOG_FILE"
            LOOP_NAME="$LOOP_NAME" PLAN_FILE="$PLAN_FILE" AGENT_MODEL="$AGENT_MODEL" \
                bash "$resolver" >> "$LOG_FILE" 2>&1 || true
        else
            echo "[WARN] ${#conflicts[@]} conflicts. No resolver script found." | tee -a "$LOG_FILE"
            echo "       Manual resolution required. See ${pending}" | tee -a "$LOG_FILE"
        fi
    fi
}

# ======================================================================
# PHASE E — Verification
# ======================================================================
run_verify() {
    echo "" | tee -a "$LOG_FILE"
    echo "=== PHASE E: Verification ===" | tee -a "$LOG_FILE"

    cd "${PROJECT_DIR}"

    # Run custom verification commands
    if [ -n "$VERIFY_COMMANDS" ]; then
        while IFS= read -r cmd; do
            [ -z "$cmd" ] && continue
            echo "Running: ${cmd}" | tee -a "$LOG_FILE"
            if eval "$cmd" >> "$LOG_FILE" 2>&1; then
                echo "  [OK]" | tee -a "$LOG_FILE"
            else
                echo "  [FAIL]" | tee -a "$LOG_FILE"
            fi
        done <<< "$VERIFY_COMMANDS"
    fi

    # Task status report
    echo "" | tee -a "$LOG_FILE"
    echo "Task status (${PLAN_FILE}):" | tee -a "$LOG_FILE"
    python3 -c "
import json
with open('${PLAN_FILE}') as f:
    tasks = json.load(f)
done = sum(1 for t in tasks if t.get('passes'))
for t in tasks:
    mark = 'DONE' if t.get('passes') else '----'
    rc = t.get('reviewer_concern', t.get('description', '')[:60])
    print(f\"  [{mark}] task {t['id']:2d} ({t.get('category',''):8s}) {rc}\")
print(f'\n  {done}/{len(tasks)} tasks complete')
" | tee -a "$LOG_FILE"
}

# ======================================================================
# CLEANUP: remove worktrees (keep branches for revertability)
# ======================================================================
cleanup_worktrees() {
    echo "" | tee -a "$LOG_FILE"
    echo "Cleaning up worktrees (branches preserved for revert)..." | tee -a "$LOG_FILE"
    for tid in "${ANALYSIS_TASKS[@]}" "${WRITING_TASKS[@]}"; do
        wt="${WT_BASE}/task${tid}"
        if git worktree list --porcelain | grep -q "worktree ${wt}$"; then
            git worktree remove --force "${wt}" 2>/dev/null || true
        fi
    done
    echo "Worktrees removed. Branches ${LOOP_NAME}/task* kept." | tee -a "$LOG_FILE"
}

# ======================================================================
# MAIN
# ======================================================================
case "$PHASE" in
    all)
        run_preflight
        run_analysis_phase
        run_writing_phase
        run_integrate
        run_verify
        cleanup_worktrees
        ;;
    preflight) run_preflight ;;
    analysis)  run_analysis_phase ;;
    writing)   run_writing_phase ;;
    integrate) run_integrate ;;
    verify)    run_verify ;;
    continue)
        run_analysis_phase
        run_writing_phase
        run_integrate
        run_verify
        cleanup_worktrees
        ;;
    *)
        echo "Usage: $0 [all|preflight|analysis|writing|integrate|verify|continue] [config.sh]"
        exit 1
        ;;
esac

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "${LOOP_NAME} FINISHED — $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Logs:   ${LOG_DIR}/"                      | tee -a "$LOG_FILE"
echo "Status: python3 -c \"import json; tasks=json.load(open('${PLAN_FILE}')); print(sum(1 for t in tasks if t.get('passes')), '/', len(tasks), 'complete')\"" | tee -a "$LOG_FILE"
echo "Revert: git reset --hard ${BASELINE_TAG}   # full rollback" | tee -a "$LOG_FILE"
echo "        git revert <merge-sha>             # one task only" | tee -a "$LOG_FILE"
