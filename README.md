# worktree-agent-loop

**Parallel AI agents in isolated git worktrees**

A framework for running parallel [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents in isolated git worktrees, each executing one task from a JSON plan, then merging results back into the main branch with full revertability.

Born from 44 iterations of autonomous manuscript editing on a marine metagenomics paper (internally called "RALPH" — Recursive Autonomous Loop for Parallel Headless agents). Battle-tested across ~200 parallel agent invocations with zero data loss.

## How it works

```
Phase A (sequential)     Preflight checks, baseline git tag
         │
Phase B (parallel)       Analysis tasks in isolated worktrees
         │                 ┌─ worktree/task1 ─── claude agent ─── commit
         │                 ├─ worktree/task2 ─── claude agent ─── commit
         │                 └─ worktree/task3 ─── claude agent ─── commit
         │
Phase C (parallel)       Writing tasks in isolated worktrees
         │                 ┌─ worktree/task4 ─── claude agent ─── commit
         │                 └─ worktree/task5 ─── claude agent ─── commit
         │
Phase D (sequential)     Merge branches into main (--no-ff)
         │                 Auto-resolve conflicts via Claude
         │
Phase E (sequential)     Verification (compile, test, audit)
```

Each task gets its own git branch and worktree. Agents run in parallel without interfering with each other. Merges are `--no-ff` so any task can be reverted with `git revert <merge-sha>`.

## Quick start

```bash
# 1. Clone into your project
cp ralph.sh ralph_merge_drivers.sh ralph_resolve_conflicts.sh /path/to/project/

# 2. Create your mission files
#    - myloop_plan.md      (JSON task array)
#    - myloop_PROMPT.md    (agent instructions)
#    - myloop_activity.md  (empty progress log)
#    - myloop_config.sh    (mission configuration)

# 3. Run
cd /path/to/project
bash ralph.sh all myloop_config.sh
```

## File structure

```
ralph.sh                      # The engine (reusable across projects)
ralph_merge_drivers.sh        # Git merge drivers for plan/activity files
ralph_resolve_conflicts.sh    # Auto-resolve merge conflicts via Claude
examples/
  manuscript_review_config.sh # Full config for scientific manuscript editing
  minimal_config.sh           # Simplest possible config
  example_plan.md             # Example JSON plan file
```

## Mission config

The config file is a bash script that exports variables consumed by `ralph.sh`:

```bash
# Required
LOOP_NAME="myloop"                    # Names files, branches, tags, logs
PROJECT_DIR="/path/to/project"        # Git repo root
ANALYSIS_TASKS_STR="1 2 3"            # Task IDs for Phase B (parallel)
WRITING_TASKS_STR="4 5"               # Task IDs for Phase C (parallel)

# Required files (must exist in PROJECT_DIR)
PLAN_FILE="myloop_plan.md"            # JSON task array
ACTIVITY_FILE="myloop_activity.md"    # Progress log
PROMPT_FILE="myloop_PROMPT.md"        # Agent instructions

# Optional
REVIEW_FILE="reviews.txt"             # Reference doc injected into prompts
WORKER_ITER=3                         # Retry budget per task
AGENT_MODEL="claude-opus-4-6"         # Claude model
ALLOWED_TOOLS="Read,Edit,Write,..."   # Tool allowlist
CONTEXT_FILES="/path/to/CLAUDE.md"    # @-referenced in task prompts
VERIFY_COMMANDS="make test"           # Phase E verification (one per line)

# Optional: custom task prompt body
ralph_task_prompt_body() {
    local task_id="$1" wt="$2" branch="$3"
    cat <<EOF
    # Your custom per-task instructions here
EOF
}
```

## Plan file format

A JSON array where each task has:

```json
[
  {
    "id": 1,
    "category": "analysis",
    "priority": 1,
    "passes": false,
    "reviewer_concern": "R1#2 (description of the concern)",
    "description": "What the agent should do. Be specific: name scripts to create, files to edit, values to compute, commit messages to use."
  }
]
```

- `id`: Unique integer. Becomes the branch name (`myloop/task1`).
- `category`: `"analysis"` or `"writing"`. Determines which phase runs it.
- `priority`: Lower = higher priority (used when agents pick tasks sequentially).
- `passes`: Set to `true` by the agent when the task is complete.
- `description`: The full task specification. This is what the agent reads.

## Key design decisions

**Why worktrees?** Git worktrees give each agent a fully isolated copy of the repo. No file locking, no race conditions, no partial writes. Each agent commits to its own branch. The merge step is where conflicts surface, and they're handled systematically.

**Why `--no-ff` merges?** Every task produces a merge commit on main. `git revert <merge-sha>` cleanly undoes exactly one task without touching others. Full revertability at task granularity.

**Why analysis before writing?** Analysis tasks produce data files (scripts, computed statistics). Writing tasks consume those data files to edit prose. Running analysis first ensures writing tasks have real numbers to work with.

**Why custom merge drivers?** The plan file and activity log are edited by every agent. Without merge drivers, every merge would conflict on these files. The plan driver OR-merges `passes` flags; the activity driver unions dated entries. Zero manual resolution needed for state files.

**Why a conflict resolver?** When two writing tasks edit the same paragraph of `main.tex`, git can't auto-merge. The resolver invokes Claude with a narrow prompt: "keep both contributions, remove conflict markers, compile." This handles 90%+ of real conflicts without human intervention.

## Revertability

```bash
# Full rollback to pre-loop state
git reset --hard myloop-baseline

# Revert one task only
git log --oneline --merges | grep "task 3"
git revert <merge-sha>

# See what each task changed
git diff myloop-baseline..myloop/task3
```

## Phase control

Run individual phases for debugging or recovery:

```bash
bash ralph.sh preflight config.sh    # Just check files + tag
bash ralph.sh analysis  config.sh    # Run analysis tasks only
bash ralph.sh writing   config.sh    # Run writing tasks only
bash ralph.sh integrate config.sh    # Merge branches only
bash ralph.sh verify    config.sh    # Compile + status report
bash ralph.sh continue  config.sh    # Skip preflight, run rest
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` command available)
- Git 2.15+ (worktree support)
- Python 3.6+ (plan/activity file manipulation)
- Bash 4+ (associative arrays)

## Origin

Developed during the writing of an ocean metagenomics manuscript analyzing 221.9 million algal protein sequences across 2,357 samples. 44 RALPH iterations handled everything from initial data audits through peer reviewer responses, each loop running 4-11 parallel agents editing LaTeX, running Python analyses, and merging results — with zero data loss across ~200 parallel agent invocations.

## License

MIT
