# p-ralph: loop lifecycle and operational guide

> This document describes how to set up and run p-ralph effectively on any
> project. The underlying methodology is
> [Geoffrey Huntley's Ralph Wiggum loop](https://ghuntley.com/ralph/) —
> p-ralph extends it with parallel worktrees and merge drivers. For
> Huntley's full methodology, see
> [Clayton Farr's Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook).

## How the Ralph loop works

The core idea (Huntley's): a bash loop repeatedly invokes a fresh AI agent,
each time feeding it the same prompt file. The agent reads a plan file from
disk, picks one task, does it, updates the plan, commits, and exits. The
bash loop restarts immediately with a clean context window. The plan file on
disk is the only shared state between iterations.

```
while :; do cat PROMPT.md | claude -p ; done
```

That's the entire orchestrator. Everything else — task selection, implementation,
testing, committing — happens inside the agent, steered by what the prompt
tells it to read.

p-ralph extends this to run N tasks simultaneously in isolated git worktrees,
then merges them back. But the per-task loop inside each worktree is still
Huntley's pattern: one agent, one task, fresh context, plan as state.

## The five phases (p-ralph specific)

1. **Plan** — read `<loop>_plan.md`, identify tasks where `passes: false`
2. **Branch** — tag the current target branch as baseline, create one worktree+branch
   per pending task off that tag
3. **Work** — spawn one Claude agent per worktree in parallel (up to
   `max_parallel`), each receiving a task-scoped prompt
4. **Integrate** — merge each successful task branch into the target with `--no-ff`, using
   custom merge drivers for plan/activity files and an LLM conflict
   resolver for real source overlaps
5. **Verify** — run `integrate_verify_cmd` on the merged target

## Setting up a new project

### 1. Initialize

```bash
cd /path/to/your/repo
p-ralph init my-loop
```

This creates four files:
- `.p-ralph.yaml` — configuration (edit this first)
- `my-loop_plan.md` — task list (JSON array)
- `my-loop_activity.md` — completion log
- `my-loop_loop.sh` — the loop runner script

Commit the generated files and your prompt before building. The runner refuses
to modify a target worktree containing staged, unstaged, or untracked changes.
Add `.pralph-worktrees/` and `<loop>_logs/` to the project's ignore rules.

### 2. Configure `.p-ralph.yaml`

The critical settings:

```yaml
verify_cmd: "pytest -x --no-header -q"    # what proves a task worked
prompt_template: "my-loop_PROMPT.md"       # what the agent reads each iteration
build_artifacts:                           # verify-step outputs to ignore during merge
  - main.pdf
max_parallel: 4                            # tune to your API rate limit and CPU
```

`verify_cmd` is your backpressure — the gate that prevents bad work from
landing. It runs inside each task's worktree after the agent finishes. The
configured `integrate_verify_cmd` then runs on the merged target (or reuses
`verify_cmd` when empty). If either exits non-zero, the run fails. Good verify
commands: `pytest`, `tectonic main.tex`, `cargo test`,
`npm test`, a custom validation script.

### 3. Write the plan file

The plan is a JSON array. Each task needs `id`, `description`, and `passes`:

```json
[
  {"id": 1, "description": "Add input validation to the upload endpoint", "passes": false},
  {"id": 2, "description": "Write integration tests for the auth flow", "passes": false},
  {"id": 3, "description": "Refactor the config loader to use dataclasses", "passes": false}
]
```

You can add any extra fields you want (`category`, `priority`, `notes`) —
the merge driver preserves them. The `passes` flag is the only one with
special semantics: the merge driver ORs it (if either branch says done,
it's done).

### 4. Write the prompt template

This is the most important file. It's what the agent reads at the start of
every iteration. p-ralph substitutes `{{TASK_ID}}` with the current task's
id before handing it to Claude.

A good prompt template follows Huntley's structure:

```markdown
# Phase 0: Orient
Read `my-loop_plan.md` and find task {{TASK_ID}}.
Study the codebase to understand what exists. Do not assume something
is missing — search first.

# Phase 1: Implement
Implement the task described in the plan. One task only.

# Phase 2: Validate
Run the project's test suite. All tests must pass.
If tests fail, fix the issue before proceeding.

# Phase 3: Record and commit
Update `my-loop_plan.md`: set task {{TASK_ID}} passes to true.
Append a dated entry to `my-loop_activity.md` describing what you did.
Stage all changes and commit with a descriptive message.

Output `<promise>COMPLETE</promise>` when done.
```

### 5. Run

```bash
p-ralph build
```

## Task design

The most common failure mode is tasks that are too big or too vague. Each
task runs in one fresh agent context — if the task requires understanding
the entire codebase or making coordinated changes across many files, the
agent will struggle.

**Good tasks:**
- Self-contained: one endpoint, one test file, one section of a document
- Verifiable: the verify command can confirm success
- Independent: doesn't require another task to be done first (all tasks
  branch off the same baseline)

**Bad tasks:**
- "Refactor the database layer" (too broad, touches everything)
- "Fix the bug" (too vague, agent doesn't know what's wrong)
- "Update X after Y is done" (dependency — task Y might not be merged yet
  when task X runs, since they branch from the same baseline)

**The one-sentence test** (from Huntley, via Farr): if you need "and" to
describe a task, it's probably multiple tasks.

Since all tasks branch off the same baseline tag, they cannot see each
other's work. Design tasks that can succeed independently. If task B truly
depends on task A's output, run them in separate `p-ralph build` invocations.

## Backpressure

Backpressure is what prevents the agent from committing broken work. Without
it, the agent will claim tasks are done when they aren't.

In Huntley's methodology, backpressure comes from tests, type checkers,
linters, and build tools — anything that exits non-zero when work is wrong.
p-ralph wires this in via `verify_cmd`:

```yaml
# For a Python project
verify_cmd: "pytest -x --no-header -q"

# For a LaTeX manuscript
verify_cmd: "tectonic main.tex"

# For a Rust project
verify_cmd: "cargo test --quiet"

# For a JS project with multiple checks
verify_cmd: "npm run typecheck && npm test"

# Custom validation script
verify_cmd: "./scripts/validate.sh"
```

The verify command should be fast enough to run after every task (agents
will wait for it). It should catch real problems without being so strict
that every task fails on unrelated issues.

The prompt should tell the agent to run validation *during* implementation
too, not just rely on the final verify gate. Huntley's phrasing: "run the
tests for that unit of code" — the agent should get feedback before it
commits, not after.

## Steering and tuning

Huntley's key insight: you steer the loop from outside, not inside.

**Upstream steering** (what the agent reads):
- The prompt template — instructions, guardrails, priorities
- Existing code patterns — the agent imitates what it finds
- Task descriptions — specificity matters

**Downstream steering** (what rejects bad work):
- The verify command
- Type checkers, linters, test suites
- Any gate the agent must pass before committing

When the loop produces wrong output, diagnose which direction to steer:
- Agent doing the wrong thing? → Adjust the prompt or task description
- Agent doing the right thing badly? → Add backpressure (more tests, stricter lints)
- Agent following wrong patterns? → Add correct patterns to the codebase for it to discover

**The plan is disposable.** If the plan is leading agents astray, delete it
and regenerate. The cost is one planning iteration, which is cheap compared
to agents going in circles.

## Plan file as persistent state

The plan file is the only communication channel between iterations. Each
agent reads it to find its task, and writes back to it when done (flipping
`passes: true`). In parallel mode, p-ralph's merge driver handles the
concurrent writes by OR-ing the `passes` flags — if either branch marks a
task complete, the merged plan marks it complete.

The activity file serves a similar role as an append-only log. The merge
driver takes the union of entries keyed by task id, keeping the longer
version when both sides have an entry for the same task.

## The `<promise>COMPLETE</promise>` signal

The prompt asks the agent to output this string when it believes it is done.
The runner requires the exact marker in the task log after a successful agent
exit and before verification. A missing marker fails that worker and prevents
integration, alongside the process-status and verification gates.

## Security

p-ralph does not enable permission-bypass flags by default. Any optional
worker flags are explicit configuration and should be reviewed before an
unattended run.

Run in sandboxed environments with minimum viable access and expose only the
credentials and resources each task needs.

## Conflict resolution

When parallel tasks edit overlapping regions of the same file, p-ralph's
merge drivers can't help — these are real content conflicts. p-ralph hands
them to a separate Claude invocation with a tight prompt: read the conflict
markers, keep both contributions, run the verify command, and finalize the
merge. The resolver is forbidden from aborting the merge (see
`docs/design/phase-d-lessons.md` for why).

If the resolver can't fix it, the merge is flagged for human review. The
other tasks' merges are unaffected — each is a separate `--no-ff` merge
commit that can be independently reverted.

## Files reference

After `p-ralph init my-loop`:

```
your-repo/
├── .p-ralph.yaml              # Config: verify_cmd, prompt path, parallel count
├── my-loop_plan.md            # JSON task list (the persistent shared state)
├── my-loop_activity.md        # Dated completion log
├── my-loop_loop.sh            # The loop runner (committed, executable)
├── my-loop_PROMPT.md          # Your prompt template (you create this)
└── .pralph-worktrees/         # Created at runtime, one dir per task
    ├── task1/
    ├── task2/
    └── ...
```

p-ralph's own code (installed separately):

```
p-ralph/
├── bin/p-ralph                # CLI entry point
├── lib/
│   ├── install_merge_drivers.sh
│   ├── resolve_with_claude.sh
│   └── merge_drivers/
│       ├── plan.py            # OR-merge for passes flags
│       └── activity.py        # Section union for activity logs
├── templates/                 # Scaffolding templates
├── examples/                  # Example configs for different project types
└── docs/
    ├── overview.md            # This file
    ├── design/                # Design rationale
    └── legacy/                # Huntley/Farr reference material
```
