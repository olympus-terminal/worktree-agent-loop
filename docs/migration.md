# Migration Guide

## From Single-Branch Ralph Loops to Worktrees

### Before: Numbered Ralph Loops on Main

```
MANUSCRIPT/
├── main.tex
├── ralph27.sh            # KAN-CCA work
├── ralph27_PROMPT.md
├── ralph27_plan.md
├── ralph27_activity.md
├── ralph28.sh            # Dark proteome work
├── ralph28_PROMPT.md
├── ralph28_plan.md
├── ralph28_activity.md
├── ralph30.sh            # Figure generation
├── ...
└── CLAUDE.md             # Complex concurrency rules
```

Problems:
- All agents edit `main.tex` on the same branch
- CLAUDE.md needs elaborate "re-read before edit" rules
- Agent collisions cause silent overwrites or failed edits
- Ralph numbers are meaningless (`ralph27` = what again?)

### After: Named Worktrees

```
MANUSCRIPT/               # main branch (human's copy)
├── main.tex
├── .wt/
│   └── config.toml
└── CLAUDE.md             # Simplified: no concurrency rules needed

../worktrees/
├── kan-cca/              # wt/kan-cca branch
│   ├── main.tex
│   ├── ralph_kan-cca.sh
│   ├── ralph_kan-cca_PROMPT.md
│   ├── ralph_kan-cca_plan.md
│   └── CLAUDE.md         # "You own this worktree"
├── dark-proteome/        # wt/dark-proteome branch
│   └── ...
└── figures/              # wt/figures branch
    └── ...
```

Benefits:
- Each agent has its own copy of every file
- No concurrency rules needed — Write is safe
- Names describe purpose
- Failed experiments can be discarded (delete worktree, delete branch)

### Migration Steps

1. **Initialize wt in your project**

```bash
cd ~/Documents/projects/MY-PROJECT/MANUSCRIPT
wt init
# Edit .wt/config.toml
```

2. **For each active ralph loop, create a worktree**

```bash
# ralph27 was doing KAN-CCA work
wt create kan-cca --from main
```

3. **Copy your existing plan into the new format**

```bash
# Adapt ralph27_plan.md -> worktrees/kan-cca/ralph_kan-cca_plan.md
# The format is the same: JSON tasks with "passes": true/false
```

4. **Customize the prompt**

Edit `ralph_kan-cca_PROMPT.md` — the template gives you a good starting point. Add any domain-specific instructions from your old `ralph27_PROMPT.md`.

5. **Launch**

```bash
wt launch kan-cca 10
```

6. **When done, merge back**

```bash
wt merge kan-cca
wt destroy kan-cca --delete-branch
```

### What About Existing Ralph Files?

You can leave old `ralph27.sh` etc. in the repo as historical artifacts, or archive them:

```bash
mkdir -p archive/ralph-loops
mv ralph2*.sh ralph2*_*.md archive/ralph-loops/
git add archive/ && git commit -m "Archive old ralph loop files"
```

### Simplifying CLAUDE.md

With worktrees, you can remove concurrency rules from CLAUDE.md:

**Remove**:
- "ALWAYS re-read the file immediately before editing"
- "Use the Edit tool with specific old_string matches, NEVER the Write tool on shared files"
- "Use narrow, unique old_string context"
- Multi-agent concurrency rules section

**Replace with**:
- "You own this worktree — edit freely"
- "Do NOT push, merge, or rebase"

The worktree CLAUDE.md template handles this automatically.
