# LaTeX Merging Strategies

## The Challenge

LaTeX manuscripts are monolithic text files. Two agents editing `main.tex` will produce merge conflicts even if they worked on different sections. Standard `git merge` treats the whole file as one unit and reports line-level conflicts.

## Strategy 1: Section Isolation (Recommended)

The best approach: each worktree only edits specific sections.

**Setup**: When creating tasks in `plan.md`, assign sections explicitly:
```json
{"id": 1, "task": "Tighten Methods section (lines 200-450 only)", "passes": false}
```

**Merge**: If both agents stayed in their lanes, `git merge` succeeds with no conflicts.

## Strategy 2: Section-Split Merge

When conflicts do occur, `wt merge` uses section-level splitting:

1. Split base/ours/theirs at `\section{}` boundaries into numbered files
2. Three-way merge each section independently
3. Most sections merge cleanly (only one side changed)
4. Generate a conflict report for the remaining sections

```bash
# Manual usage of the tools:
python3 lib/latex-merge/section-split.py main.tex sections/
# ... resolve conflicts in individual section files ...
python3 lib/latex-merge/section-merge.py sections/ main_merged.tex
```

### How It Works

```
main.tex (base)
├── 000_preamble.tex
├── 001_introduction.tex
├── 002_methods.tex          ← Agent A edited this
├── 003_results.tex          ← Agent B edited this
└── 004_discussion.tex

After section-split:
- 002_methods.tex: only Agent A's version exists → clean merge
- 003_results.tex: only Agent B's version exists → clean merge
- Other sections: identical → no conflict
```

## Strategy 3: Additive-Only Editing

For tasks that only add content (new paragraphs, new figures), conflicts are rare because additions at different locations merge cleanly.

**Best for**: Adding supplemental sections, inserting new figures, expanding existing paragraphs at different points.

## Strategy 4: Bibliography Union Merge

`.bib` and `.bbl` files use git's union merge driver (configured by `wt init` in `.gitattributes`):

```
*.bib merge=union
*.bbl merge=union
```

Union merge keeps both sides' additions. Since bibliography entries are independent blocks, this almost always produces correct results. Duplicate entries can be cleaned up afterward.

## Conflict Report

When `wt merge` encounters conflicts, it runs `conflict-report.py`:

```
Conflict Report: main.tex
============================================================
Total conflicts: 2

Section: Methods
----------------------------------------
  Conflict 1 (lines 234-251):
    Ours (wt/kan-cca): 8 line(s)
    Theirs (wt/figures): 10 line(s)
    Ours preview:
      | We applied sparse canonical correlation analysis (CCA)
      | with $\ell_1$ regularization to the domain abundance
      | matrix ($n = 441$ assemblies, $p = 2{,}847$ Pfam domains).
    Theirs preview:
      | Figure~\ref{fig:cca} shows the canonical correlation
      | analysis results across all assemblies.
```

This tells you exactly where the conflicts are and what each agent wrote, so you can make an informed decision.

## Recommendations

1. **Plan section ownership** when creating worktrees — this avoids most conflicts
2. **Use union merge for .bib** — configured automatically by `wt init`
3. **Prefer section-split** over manual resolution for large conflicts
4. **Merge frequently** — smaller merges = fewer conflicts
