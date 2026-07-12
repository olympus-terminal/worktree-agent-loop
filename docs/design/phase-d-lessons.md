# Phase D lessons — why p-ralph has merge drivers

This document records the specific bug that motivated the merge-driver
machinery in p-ralph. If you're tempted to "simplify" it, read this first.

## Setting

The TARA-Oceans manuscript project ran a loop called `ralph43` — 11 tasks
to preempt simulated peer-review criticism. The loop was parallelized with
git worktrees following the ralph42 convention: each task got its own
branch (`ralph43/task1`, `ralph43/task2`, ...) off a shared baseline tag,
and ran to completion in an isolated Claude iteration. This is exactly the
pattern p-ralph generalizes.

Phase D (integrate) was supposed to merge all nine successful task branches
back into `main` with `git merge --no-ff`. All nine merges failed.

## What went wrong

Two independent causes compounded:

1. **A worker helper pre-wrote plan/activity files in `main` before merging**
   so it could display progress during the run. That left the working tree
   dirty when the merge step tried to run. `git merge` refuses a merge into
   a dirty tree.
2. **The verify step compiled the manuscript** (`tectonic main.tex`),
   producing a new `main.pdf` in the working tree. Even with the plan file
   hack removed, `main.pdf` alone was enough to block every merge.

When `git merge` refused, the wrapper script ran `git merge --abort`
silently and moved on. The plan file on disk still said every task had
`passes: true`, because the workers had written that to their own branches.
A human reading the plan would conclude all tasks were merged — they were
not.

## Why naive fixes don't work

- **"Just don't write plan.md from the main wrapper"**: works for this one
  bug, but ignores the deeper problem. Each worker's branch diverges from
  every other worker's branch on plan.md and activity.md, because each
  worker's final act is to flip *its own* `passes` flag and append *its
  own* dated entry. Sequential merges therefore create plan.md conflicts
  on task 2 onward even when no source code conflicts exist.
- **"Serialize the merges"**: defeats the purpose of parallel worktrees.
- **"Commit the build artifact"**: pollutes history with multi-MB PDFs.
- **"Add `main.pdf` to `.gitignore`"**: doesn't help — `git merge` checks
  the working tree, not the index.

## The fix, as now baked into p-ralph

### 1. Custom merge driver for the plan file

`lib/merge_drivers/plan.py` takes three files (ancestor, ours, theirs) and
produces a merged plan that is the task-id-wise OR of the `passes` flags.
Concretely: if task 5 is `passes: true` on either side, it's `passes:
true` in the result. This is correct for a completion flag — nobody ever
flips a task back from done to not-done, so OR is idempotent and
commutative.

### 2. Custom merge driver for the activity file

`lib/merge_drivers/activity.py` splits both files on "## YYYY-MM-DD — Task N
complete" section headers, keys entries by task id, and emits the union in
task-id order. If both sides have an entry for the same task, the longer
one wins (longer usually means more detail survived a rewrite). Entries are
ordered deterministically so the merge is stable.

### 3. Build artifacts as `merge=ours`

`main.pdf` and any other verify-step output is registered in
`.git/info/attributes` as `merge=ours`, which makes git take the target
branch's side unconditionally and never even attempt a three-way merge. The
runner refuses to start unless the target worktree is clean, so integration
never hides user edits in an unattended stash.

### 4. Conflict resolver as a fallback, not a first resort

Even with the merge drivers, real source conflicts happen when two tasks
edit overlapping lines of the same `.tex` or `.py` file. These are routed
to a Claude invocation with a tight prompt: keep-both-contributions
semantics, compile-verify, and `git commit --no-edit` to finalize the
merge. The resolver is never allowed to `git merge --abort` or `git
reset` — those were the silent failure modes in the original bug.

## What the ralph43 data showed after the fix

- 5 of 9 task branches merged cleanly via the merge drivers alone
- 4 of 9 had real overlapping `.tex` edits; all resolved by Claude on the
  first conflict-resolver pass
- Final compile of `main.tex` and `supplemental_information.tex` succeeded
- Net diff: 75 insertions, 45 deletions across the two .tex files
- Every merge was `--no-ff`, so any single task can still be reverted via
  `git revert <merge-sha>` without disturbing the others

## The p-ralph invariants that came out of this

1. Never write plan/activity files in the target branch from the wrapper — only from
   inside task branches.
2. Never run the verify step inside the target *during* integrate; run it in a
   worktree or after all merges are done.
3. Always install the merge drivers before the first merge, not after a
   conflict. The drivers are idempotent; reinstalling is free.
4. Refuse to start when the target has staged, unstaged, or untracked changes.
   Never move the user's in-progress work into an unattended stash.
5. When a conflict resolver runs, it must complete the merge or fail
   loudly. Silent `git merge --abort` is banned.
