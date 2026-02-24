# HPC Integration

## Overview

`wt` integrates with SLURM-based HPC clusters through three mechanisms:

1. **Job tagging** — `--comment=wt/<name>` on every sbatch call
2. **Output isolation** — each worktree's jobs write to their own log directory
3. **Remote querying** — `wt hpc` queries the cluster via SSH

## Job Tagging

Every SLURM job submitted from a worktree should include:

```bash
#SBATCH --comment=wt/kan-cca
```

This is automatically included when using the `sbatch-header.sh.tmpl` template.

### Why `--comment`?

- Zero infrastructure: built into SLURM, no plugins needed
- Queryable: `squeue --format` includes the comment field
- Non-intrusive: doesn't affect job execution
- Any cluster: works on any SLURM installation

### Querying Tagged Jobs

```bash
# All jobs for a worktree
wt hpc --worktree kan-cca

# All wt-tagged jobs
wt hpc

# Manual query
ssh user@cluster "squeue -u user --format='%.10i %.25j %.8T %.50Z' | grep wt/"
```

## Output Isolation

Each worktree should use its own log directory on the cluster:

```bash
#SBATCH --output=/scratch/user/logs/wt_kan-cca/%x_%j.out
#SBATCH --error=/scratch/user/logs/wt_kan-cca/%x_%j.err
```

Create the directory structure when setting up HPC work:

```bash
ssh user@cluster "mkdir -p /scratch/user/logs/wt_kan-cca"
```

## Rsync Patterns

Pull results from a worktree's HPC outputs:

```bash
# Pull specific results
rsync -avz user@cluster:/scratch/user/results/wt_kan-cca/ \
    worktrees/kan-cca/results/

# Pull job logs
rsync -avz user@cluster:/scratch/user/logs/wt_kan-cca/ \
    worktrees/kan-cca/logs/
```

## Configuration

Set HPC connection details in `.wt/config.toml`:

```toml
[hpc]
host = "cluster.example.edu"
user = "myuser"
scratch = "/scratch/myuser"
conda_env = "myenv"
partition = "compute"
```

## Template Usage

The `sbatch-header.sh.tmpl` template generates a complete SLURM header:

```bash
#!/bin/bash
#SBATCH --job-name=kan-cca_my_analysis
#SBATCH --partition=compute
#SBATCH --comment=wt/kan-cca
#SBATCH --output=/scratch/myuser/logs/%x_%j.out
#SBATCH --error=/scratch/myuser/logs/%x_%j.err
#SBATCH --time=04:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4

set -euo pipefail
module purge
source activate myenv
```

## Best Practices

1. **Always tag jobs** — untagged jobs are invisible to `wt hpc`
2. **Isolate outputs** — don't let different worktrees overwrite each other's results
3. **Use rsync for results** — pull HPC outputs into the worktree for analysis
4. **Check before merge** — ensure all HPC jobs are complete before merging back
