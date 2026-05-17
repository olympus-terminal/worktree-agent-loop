# Philosophy: Why Worktrees

## The Problem

Research manuscripts evolve through parallel workstreams: one agent refines figures, another runs HPC pipelines, a third tightens prose. When these share a single working tree, every agent must:

1. Re-read files before every edit (another agent may have changed them)
2. Use narrow, targeted edits that fail safely on stale content
3. Commit constantly to make changes visible to other agents
4. Avoid touching the same section of the same file

This works — we proved it on TARA-OMEN with 5+ concurrent ralph loops — but it's fragile. A single Write instead of Edit can silently overwrite hours of another agent's work.

## The Solution: One Worktree Per Agent

Git worktrees give each agent its own copy of the repository on its own branch:

```
project/                  # main branch (human's working copy)
../worktrees/kan-cca/     # wt/kan-cca branch (agent 1)
../worktrees/figures/     # wt/figures branch (agent 2)
../worktrees/prose/       # wt/prose branch (agent 3)
```

Each agent owns its worktree exclusively. No concurrent editors means:
- Write is safe (no overwrites)
- No need to re-read before editing
- No need for narrow edit contexts
- No need for constant commits to synchronize

## When Worktrees Are Better

| Scenario | Shared tree | Worktrees |
|----------|-------------|-----------|
| Agents editing different files | Works fine | Works fine |
| Agents editing same file | Fragile | Each edits their copy, merge later |
| Agent does destructive refactor | Risky | Isolated, merge when ready |
| Agent runs long HPC pipeline | Others must not break state | Isolated |
| Failed experiment | Must carefully revert | Just delete the worktree |

## When a Shared Tree Is Fine

- Single agent at a time
- Quick, non-overlapping tasks
- Tasks that don't modify shared files (e.g., only creating new scripts)

## The Merge Tax

Worktrees shift complexity from "concurrent editing" to "merging." For LaTeX manuscripts, this is a good trade because:

1. **Section-level splitting** makes merges surgical — if agent A edits Methods and agent B edits Results, there's no conflict
2. **Bibliography files** use union merge — both agents can add references
3. **Figures and scripts** rarely conflict (agents work on different ones)
4. **The human decides** — merge conflicts surface as a report, not as silently lost work

## Design Principles

1. **No daemon, no database** — state lives in git and markdown files
2. **Name-based, not numbered** — `wt/kan-cca` tells you what it does; `ralph32` does not
3. **Fail loud, not silent** — a merge conflict is better than overwritten work
4. **Zero infrastructure** — bash + git + python3 stdlib, nothing to install
5. **HPC-native** — SLURM job tagging via `--comment`, SSH-based queries
