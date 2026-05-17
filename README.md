# wt — Git Worktree Orchestration for Multi-Agent Projects

A toolkit for running multiple Claude Code agents in parallel on research manuscripts, each in its own git worktree. Born from the TARA-OMEN project's battle-tested "ralph loop" pattern.

## Why

When multiple AI agents work on the same manuscript simultaneously, they collide: overwriting each other's edits, re-reading files defensively, and fighting over shared state. Git worktrees solve this by giving each agent its own copy of the repository on its own branch.

See [docs/philosophy.md](docs/philosophy.md) for the full rationale.

## Install

```bash
git clone <repo-url> ~/worktrees
echo 'export PATH="$HOME/worktrees/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Requirements**: bash, git, python3 (stdlib only). No external dependencies.

## Quickstart

```bash
# 1. Initialize your project
cd ~/my-manuscript
wt init
# Edit .wt/config.toml with your settings

# 2. Create worktrees for parallel tasks
wt create kan-cca --from main
wt create figures --from main

# 3. Edit the task plans
vim ../worktrees/kan-cca/ralph_kan-cca_plan.md
vim ../worktrees/figures/ralph_figures_plan.md

# 4. Launch agents
wt launch kan-cca --bg
wt launch figures --bg

# 5. Monitor progress
wt status

# 6. Merge completed work back
wt merge kan-cca
wt merge figures

# 7. Clean up
wt destroy kan-cca --delete-branch
wt destroy figures --delete-branch
```

## Commands

| Command | Description |
|---------|-------------|
| `wt init` | Initialize repo for worktree workflow |
| `wt create <name>` | Create worktree + branch + agent scaffold |
| `wt launch <name>` | Run ralph loop in worktree |
| `wt status` | Dashboard of all worktrees |
| `wt merge <name>` | Merge branch back (LaTeX-aware) |
| `wt destroy <name>` | Remove worktree |
| `wt hpc` | Query HPC jobs tagged to worktrees |

Run `wt <command> --help` for detailed options.

## How It Works

### Worktree Lifecycle

```
create → launch → (iterate) → merge → destroy
```

1. **Create** — `git worktree add` + scaffold ralph loop files
2. **Launch** — Run the ralph loop (Claude CLI in a loop, one task per iteration)
3. **Merge** — `git merge --no-ff` with LaTeX section-split on conflicts
4. **Destroy** — `git worktree remove` + optional branch deletion

### Ralph Loop

Each worktree contains a self-contained ralph loop:

```
worktree/
├── ralph_<name>.sh          # Loop script (runs Claude iteratively)
├── ralph_<name>_PROMPT.md   # What the agent sees each iteration
├── ralph_<name>_plan.md     # JSON task list with "passes": true/false
├── ralph_<name>_activity.md # Timestamped log of what happened
└── CLAUDE.md                # Worktree-specific instructions
```

The loop runs Claude, which reads the plan, executes one task, marks it done, and commits. Repeat until all tasks pass.

### LaTeX Merge Strategy

When merging produces conflicts in `.tex` files:

1. Split at `\section{}` boundaries
2. Three-way merge per section
3. Generate a human-readable conflict report
4. `.bib` files use union merge (both sides' refs survive)

See [docs/latex-merging.md](docs/latex-merging.md).

### HPC Integration

Tag SLURM jobs with `--comment=wt/<name>` for tracking:

```bash
#SBATCH --comment=wt/kan-cca
```

Query with `wt hpc --worktree kan-cca`. See [docs/hpc-integration.md](docs/hpc-integration.md).

## Configuration

`wt init` creates `.wt/config.toml`:

```toml
[project]
name = "my-manuscript"
base_branch = "main"
worktree_dir = "../worktrees"

[agent]
model = "opus"
max_iterations = 20

[hpc]
host = "cluster.example.edu"
user = "myuser"
scratch = "/scratch/myuser"

[latex]
compiler = "tectonic"
main_file = "main.tex"
```

See [config/wt.toml.example](config/wt.toml.example) for all options.

## Migration

Coming from numbered ralph loops (`ralph27.sh`, `ralph28.sh`, ...)? See [docs/migration.md](docs/migration.md).

## Design Decisions

- **Generic first** — templates use `{{VARIABLE}}` placeholders; project-specific details live in config
- **Name-based worktrees** — `wt/kan-cca` not `ralph32`; names describe purpose
- **No daemon, no database** — all state in git + markdown files
- **Bash CLI, Python merge tools** — bash for git/ssh, Python for LaTeX parsing (stdlib only)
- **SLURM `--comment` for job tagging** — zero infrastructure, works on any cluster
- **Zero external dependencies** — bash + git + python3 stdlib

## License

MIT
