# TARA-OMEN: Worktree Workflow

How the TARA-Oceans OMEN manuscript uses `wt` for multi-agent development.

## Background

TARA-OMEN is a methods paper with multiple parallel workstreams:
- **kan-cca**: KAN + Sparse CCA analysis pipeline
- **dark-proteome**: Novel domain discovery pipeline
- **figures**: Publication-quality figure generation
- **latex-trim**: Word count reduction and editing

Before `wt`, these ran as numbered "ralph loops" (`ralph27.sh`, `ralph28.sh`, ...) on a single branch with concurrency guards. Now each gets its own worktree.

## Setup

```bash
cd ~/Documents/projects/TARA-OMEN/MANUSCRIPT
wt init
# Edit .wt/config.toml (or copy from examples/tara-omen/wt.toml)
```

## Typical Session

```bash
# Create worktrees for parallel work
wt create kan-cca --from main
wt create dark-proteome --from main

# Edit plans
vim worktrees/kan-cca/ralph_kan-cca_plan.md
vim worktrees/dark-proteome/ralph_dark-proteome_plan.md

# Launch agents
wt launch kan-cca --bg
wt launch dark-proteome --bg

# Monitor progress
wt status

# Check HPC jobs
wt hpc

# When done, merge back
wt merge kan-cca
wt merge dark-proteome

# Clean up
wt destroy kan-cca --delete-branch
wt destroy dark-proteome --delete-branch
```

## HPC Integration

All SLURM jobs use `--comment=wt/<name>` for tracking:

```bash
#SBATCH --comment=wt/kan-cca
```

Query with:
```bash
wt hpc --worktree kan-cca
```

## Key Data Paths (Jubail)

| Data | Path |
|------|------|
| Protein FASTAs | `/scratch/drn2/PROJECTS/TARA-LA4SR/03_analyses/algae_proteins/` |
| Pfam results | `/scratch/drn2/PROJECTS/TARA-LA4SR/03_analyses/pfam_results/` |
| Dark proteome | `/scratch/drn2/PROJECTS/TARA-LA4SR/03_analyses/novel_domains/` |

**Important**: The protein directory is `algae_proteins`, not `algal_sequences`.
