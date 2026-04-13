# Legacy reference material

These files are preserved verbatim as the intellectual origins of the Ralph
loop pattern and its adaptation in the TARA-Oceans manuscript work. They are
retained for attribution, pedagogy, and so that future p-ralph contributors
can see how the pattern evolved.

| File | Origin | Role in p-ralph |
|------|--------|-----------------|
| `RALPH_original_guide_huntley.txt` | Geoff Huntley's original "Ralph Wiggum as software engineer" essay | Canonical description of the loop pattern — single-task-per-iteration, plan.md as persistent state, `<promise>COMPLETE</promise>` signal, fresh context per iteration. |
| `RALPH_WIGGUM_MASTER_GUIDE.md` | TARA-Oceans internal adaptation | Extended guide covering data-integrity policy, claim calibration, and verification gates used by ralph1–42. |
| `RALPH-howto.txt` | TARA-Oceans operator notes | How to drive a Ralph loop from a human operator's seat (start/stop, check progress, revert). |
| `RALPH_LOOP_FULL_PERMISSIONS_AGENT.md` | TARA-Oceans agent-side doc | What the Claude agent inside each iteration needs to know about permissions, guardrails, and the promise protocol. |

## What p-ralph adds on top of these

The legacy guides describe the serial-loop Ralph. p-ralph is the
**parallel-worktree** generalization, which adds:

- One git worktree per task, running in parallel
- Custom git merge drivers for plan/activity files (OR of passes flags,
  union of dated entries) so concurrent iterations don't stomp on each
  other's state
- Build-artifact handling (e.g. `main.pdf` as `merge=ours`) so verify-compile
  side-effects don't block merges
- An LLM-driven conflict resolver for the inevitable real source conflicts
  when parallel tasks touch overlapping files
- Per-task `--no-ff` merges so any single task can be reverted cleanly

These additions were hard-won from the ralph42 and ralph43 runs on the
TARA-Oceans manuscript. See `../design/phase-d-lessons.md` for the bug-fix
narrative that motivated the merge-driver machinery.
