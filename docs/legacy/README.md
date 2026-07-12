# Legacy reference material

> [!CAUTION]
> These archived files contain outdated permission-bypass examples and
> project-specific commands. Do not execute them. Current safe-default usage
> is documented in the repository `README.md` and `docs/overview.md`.

These files document the origins of the Ralph Wiggum loop methodology and
one project-specific adaptation. They are retained for attribution and so
that future p-ralph contributors can trace the methodology chain.

## Attribution chain

The Ralph Wiggum loop methodology is **Geoffrey Huntley's** work. The
canonical source is [ghuntley.com/ralph/](https://ghuntley.com/ralph/).
Clayton Farr wrote a structured playbook organizing Huntley's methodology
into a practical reference:
[ClaytonFarr/ralph-playbook](https://github.com/ClaytonFarr/ralph-playbook).
Huntley forked that playbook at
[ghuntley/how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum).

## Files

| File | Actual origin | What it is |
|------|---------------|------------|
| `ralph_playbook_claytonfarr.txt` | Clayton Farr's [ralph-playbook](https://github.com/ClaytonFarr/ralph-playbook), captured from Huntley's fork | Structured reference for Huntley's methodology — loop mechanics, file layout, prompt templates, key principles. Not Huntley's original essay. |
| `RALPH-howto.txt` | TARA-Oceans operator notes | Project-specific notes on how to operate a Ralph loop on the TARA-Oceans manuscript (start/stop, check progress, revert). |
| `RALPH_WIGGUM_MASTER_GUIDE.md` | TARA-Oceans internal guide | Project-specific adaptation of Huntley's methodology for a marine metagenomics manuscript. Contains hardcoded paths and biology-specific details — not a general reference. |
| `RALPH_LOOP_FULL_PERMISSIONS_AGENT.md` | TARA-Oceans agent-side doc | Project-specific agent instructions for a RuBisCO analysis task within the TARA-Oceans manuscript. |

**Note:** The TARA-Oceans files (`RALPH_WIGGUM_MASTER_GUIDE.md`,
`RALPH-howto.txt`, `RALPH_LOOP_FULL_PERMISSIONS_AGENT.md`) are examples of
applying Huntley's methodology to a specific scientific project. They are
not general-purpose guides. For Huntley's methodology itself, see the
playbook or [ghuntley.com/ralph/](https://ghuntley.com/ralph/).

## What p-ralph adds on top of Huntley's methodology

Huntley's methodology describes a serial loop — one agent, one task, repeat.
p-ralph is the **parallel-worktree** extension, which adds:

- One git worktree per task, running in parallel
- Custom git merge drivers for plan/activity files (OR of passes flags,
  union of dated entries) so concurrent iterations don't stomp on each
  other's state
- Build-artifact handling (e.g. `main.pdf` as `merge=ours`) so verify-compile
  side-effects don't block merges
- An LLM-driven conflict resolver for the inevitable real source conflicts
  when parallel tasks touch overlapping files
- Per-task `--no-ff` merges so any single task can be reverted cleanly

These additions were developed during the ralph42 and ralph43 runs on the
TARA-Oceans manuscript. See `../design/phase-d-lessons.md` for the bug-fix
narrative that motivated the merge-driver machinery.
