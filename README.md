# p-ralph

**Parallel-worktree extension of the Ralph Wiggum loop methodology.**

p-ralph implements [Geoffrey Huntley's Ralph Wiggum loop](https://ghuntley.com/ralph/)
— a methodology for driving long-horizon coding or writing tasks by letting
one fresh AI agent complete one small task per iteration, with plan state
persisted to disk between iterations. This project extends that methodology
to run **tasks in parallel** in isolated git worktrees, then merges the
results back with custom merge drivers that understand plan/activity files.

It's not a framework. It's a CLI (`p-ralph`) plus a set of templates and
merge drivers that you drop into any git repository.

## Methodology and attribution

**The Ralph Wiggum loop is Geoffrey Huntley's methodology.** The core
concepts — one task per iteration, fresh context each time, plan file as
persistent shared state, backpressure via tests/compilation, and the bash
outer loop that restarts the agent — are all Huntley's design. Clayton
Farr's [Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook)
provides an excellent structured reference for the methodology.

**What p-ralph adds** on top of Huntley's serial loop:

- Parallel git worktrees — multiple tasks run simultaneously in isolated
  branches off a shared baseline tag
- Custom merge drivers for plan files (OR of `passes` flags) and activity
  logs (section union by task id) so concurrent workers don't stomp each
  other's state
- Build-artifact handling (`merge=ours`) so verify-step outputs like
  compiled PDFs don't block merges
- An LLM-driven conflict resolver for real source-file overlaps between
  parallel tasks
- Per-task `--no-ff` merges so any single task can be reverted cleanly

These additions were developed during the ralph1–43 runs on the TARA-Oceans
oceanographic manuscript, where dozens of Claude iterations wrote verifiable
scientific text under a strict data-integrity policy. The original reference
material lives in `docs/legacy/` with attribution.

## When to use p-ralph

Use it when you have:

- A long task list that's too big for a single Claude session
- Per-task verification you can express as a shell command that exits 0/non-0
  (a test suite, a compiler, a linter, a custom script)
- A plan file and an activity log you want the agents to append to, without
  stomping on each other's writes
- A git repo you can tolerate receiving many `--no-ff` merge commits into

Don't use it when one agent in one session could plausibly finish the work,
or when your tasks are so interdependent that parallelizing them creates
more conflicts than it saves iterations.

## The five phases

Each p-ralph run executes five phases in order:

1. **Plan** — read tasks from `<loop>_plan.md`; select the pending set.
2. **Branch** — create a `<loop>-baseline` tag on `main`, then one
   `<loop>/task<N>` worktree+branch per pending task off that tag.
3. **Work** — spawn one Claude iteration per worktree in parallel, each
   handed the task-scoped prompt. On success each writes a `<promise>COMPLETE</promise>`
   signal, commits its work, and updates plan/activity files in its branch.
4. **Integrate** — stash build artifacts in `main`, install custom merge
   drivers, `git merge --no-ff` each task branch into `main`. Real source
   conflicts are handed to a one-off Claude conflict-resolver invocation.
5. **Verify** — run the configured verify command on the merged `main`. If
   it fails, the most recent merge is flagged for review but not auto-reverted.

## Install

```bash
git clone https://github.com/olympus-terminal/p-ralph.git
cd p-ralph
./install.sh   # symlinks bin/p-ralph into ~/.local/bin
```

## Quick start

```bash
cd /path/to/your/repo
p-ralph init my-loop           # writes .p-ralph.yaml and my-loop_plan.md
$EDITOR my-loop_plan.md        # fill in the tasks
p-ralph build my-loop          # run all pending tasks in parallel worktrees
p-ralph status my-loop         # see what's merged, what's pending
p-ralph revert my-loop 7       # revert task 7's merge commit, keep the rest
```

## Documentation

- `docs/overview.md` — loop lifecycle and state model
- `docs/design/phase-d-lessons.md` — why the merge drivers exist (the
  TARA-Oceans bug story)
- `docs/legacy/` — original Ralph material, preserved verbatim for
  attribution and reference

## License

MIT. See `LICENSE`.
