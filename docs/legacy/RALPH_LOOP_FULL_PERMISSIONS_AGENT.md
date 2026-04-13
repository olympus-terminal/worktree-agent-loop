# RALPH Loop (Full-Permissions) for Secondary Agent

## Mission
Integrate Myzozoan/Type II RuBisCO into the analysis and manuscript so diversity estimates are no longer biased low by Form I-only assumptions.

## Authority / Permissions
You are authorized to run with full permissions for this task:
- Full filesystem read/write access in project and parent analysis directories.
- Full network access for dependency installs and reference retrieval.
- Full execution rights for pipeline runs, figure regeneration, and manuscript edits.

Do not run destructive commands that remove unrelated work. Do not rewrite git history.

## Source Paths
- Manuscript root: `/media/drn2/External/TARA-Oceans/MANUSCRIPT`
- Master guide: `/media/drn2/External/TARA-Oceans/RALPH_WIGGUM_MASTER_GUIDE.md`
- Local guide: `/media/drn2/External/TARA-Oceans/MANUSCRIPT/RALPH_original_guide_huntley.txt`

## Loop Cadence (Ralph Cycle)
Repeat until Definition of Done is met.

### Cycle 0: Boot
1. Read both guides above and summarize constraints.
2. Snapshot current state:
- `git status`
- list key RuBisCO inputs/outputs
- list manuscript lines with RuBisCO claims (`main.tex`)
3. Create `ralph_loop_log.md` and append cycle entries each pass.

### Cycle 1..N Structure
1. **Plan (short):** pick one scoped objective for the cycle.
2. **Execute:** implement code/data/text changes.
3. **Verify:** run objective checks + compile manuscript.
4. **Log:** record changes, metrics deltas, blockers, next objective.
5. **Decide:** continue loop or stop when DoD met.

## Required Workstreams

### A) RuBisCO Model Expansion
Keep existing broad models, add supplementary fine-grained layer:
- Tier 1: current broad green/red HMMs (retain for continuity)
- Tier 2: fine-grained profiles
  - Form IB sublineages
  - Form ID sublineages
  - Myzozoan/dinoflagellate Type II
  - Chromerid Type II
  - decoys: bacterial Form II and Form IV/RLP

Implement hierarchical calling:
1. form assignment (I/II/other)
2. lineage assignment within form
3. ambiguity handling via bit-score margin threshold

### B) Recompute Outputs
Regenerate all impacted RuBisCO outputs:
- per-sample detections
- dominant-lineage calls
- RuBisCO-positive counts
- diversity lower-bound estimate
- supplementary tables/source_data artifacts

### C) Validation
Mandatory validation panel:
- curated Type II positives (dinoflagellate/chromerid)
- curated negatives (non-photosynthetic alveolates/apicomplexans)
- cross-reactivity against bacterial Form II
- threshold sensitivity (strict/default/relaxed)

Report precision/recall-style summaries where possible.

### D) Manuscript Integration
Update claims and methods consistently in `main.tex`:
- revise strong single-point claims where Type II omission previously biased estimates
- add supplementary section describing fine-grained RuBisCO panel
- ensure Results/Discussion/STAR Methods are internally consistent
- preserve main narrative while moving detail-heavy diagnostics to supplement

Minimum hotspots to check:
- `main.tex:63`
- `main.tex:99`
- `main.tex:116`
- `main.tex:152`
- `main.tex:171`
- `main.tex:215`
- `main.tex:247`
- `main.tex:259`
- `main.tex:462`

### E) Figure/Supplement Sync
Rebuild any lineage figures/tables affected by new calls.
Ensure caption numbers and supplementary references match generated outputs.

## Required Deliverables
1. Updated analysis scripts/configs for two-tier RuBisCO calling.
2. Regenerated result tables with provenance notes.
3. Manuscript patch in `main.tex` and related supplement references.
4. `source_data` delta table:
- old estimate
- Type II-inclusive estimate
- absolute and percent uplift
- sensitivity bounds
5. `ralph_loop_log.md` with per-cycle evidence.

## Verification Commands (minimum)
- `tectonic -X compile main.tex`
- run all RuBisCO-specific regeneration scripts used by this update
- sanity checks on counts consistency across text/tables

## Definition of Done
Stop loop only when all are true:
1. Type II-inclusive detection is implemented and used in outputs.
2. Key diversity estimates are updated (or explicitly labeled provisional with bounds).
3. Main text, supplement, and source tables are numerically consistent.
4. Manuscript compiles successfully.
5. Loop log contains reproducible command and output summary for each cycle.

## Handoff Format (at completion)
Provide:
1. concise summary of what changed
2. exact files edited
3. key before/after numbers
4. unresolved risks
5. rerun instructions for reproducibility
