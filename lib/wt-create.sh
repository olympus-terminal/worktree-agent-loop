#!/usr/bin/env bash
# wt-create.sh — Create worktree + branch + scaffold files

wt_create() {
    local name="" base_branch="" no_scaffold=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)  base_branch="$2"; shift 2 ;;
            --bare)  no_scaffold=true; shift ;;
            -h|--help)
                cat <<EOF
${BOLD}wt create${RESET} — Create a new worktree with agent scaffold

${BOLD}USAGE${RESET}
    wt create <name> [--from <branch>] [--bare]

Creates a git worktree on branch wt/<name>, populates it with
ralph loop scaffold files from templates.

${BOLD}ARGUMENTS${RESET}
    <name>          Worktree name (e.g., kan-cca, dark-proteome)

${BOLD}OPTIONS${RESET}
    --from <branch> Base branch (default: from config or main)
    --bare          Skip template scaffolding
    -h, --help      Show this help

${BOLD}CREATES${RESET}
    <worktree_dir>/<name>/
    ├── ralph_<name>.sh
    ├── ralph_<name>_PROMPT.md
    ├── ralph_<name>_plan.md
    ├── ralph_<name>_activity.md
    └── CLAUDE.md
EOF
                return 0
                ;;
            -*)  wt_die "Unknown option: $1" ;;
            *)   name="$1"; shift ;;
        esac
    done

    [[ -n "$name" ]] || wt_die "Usage: wt create <name> [--from <branch>]"

    # Validate name
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        wt_die "Invalid worktree name: '$name'. Use alphanumeric, hyphens, dots, underscores."
    fi

    wt_require_project
    wt_load_config

    base_branch="${base_branch:-$(wt_cfg "project_base_branch" "main")}"
    local branch_name="wt/$name"
    local wt_dir
    wt_dir="$(wt_worktree_path "$name")"

    # Pre-flight checks
    wt_branch_exists "$base_branch" || wt_die "Base branch '$base_branch' does not exist."

    if wt_branch_exists "$branch_name"; then
        wt_die "Branch '$branch_name' already exists. Use a different name or delete the branch."
    fi

    if [[ -d "$wt_dir" ]]; then
        wt_die "Directory already exists: $wt_dir"
    fi

    # Create worktree directory parent
    mkdir -p "$(dirname "$wt_dir")"

    wt_info "Creating worktree '$name' from '$base_branch'"

    # Create worktree + branch
    git -C "$WT_ROOT" worktree add -b "$branch_name" "$wt_dir" "$base_branch"
    wt_ok "Worktree created at $wt_dir (branch: $branch_name)"

    if $no_scaffold; then
        wt_ok "Scaffold skipped (--bare). Done."
        return 0
    fi

    # ── Template substitution ─────────────────────────────────────────
    local install_dir
    install_dir="$(wt_install_dir)"
    local tmpl_dir="$install_dir/templates/ralph"
    local project_name
    project_name="$(wt_cfg "project_name" "$(basename "$WT_ROOT")")"

    WT_TMPL=(
        [NAME]="$name"
        [BRANCH]="$branch_name"
        [BASE_BRANCH]="$base_branch"
        [PROJECT]="$project_name"
        [DATE]="$(date +%Y-%m-%d)"
        [TIMESTAMP]="$(wt_timestamp)"
        [MODEL]="$(wt_cfg "agent_model" "opus")"
        [MAX_ITERATIONS]="$(wt_cfg "agent_max_iterations" "20")"
        [COMPILER]="$(wt_cfg "latex_compiler" "tectonic")"
        [MAIN_FILE]="$(wt_cfg "latex_main_file" "main.tex")"
        [HPC_HOST]="$(wt_cfg "hpc_host" "")"
        [HPC_USER]="$(wt_cfg "hpc_user" "")"
        [HPC_SCRATCH]="$(wt_cfg "hpc_scratch" "")"
        [HPC_CONDA]="$(wt_cfg "hpc_conda_env" "")"
        [HPC_PARTITION]="$(wt_cfg "hpc_partition" "")"
    )

    local tmpl output
    local scaffolded=0

    # ralph loop script
    if [[ -f "$tmpl_dir/loop.sh.tmpl" ]]; then
        wt_template "$tmpl_dir/loop.sh.tmpl" "$wt_dir/ralph_${name}.sh"
        chmod +x "$wt_dir/ralph_${name}.sh"
        ((scaffolded++))
    fi

    # Prompt
    if [[ -f "$tmpl_dir/PROMPT.md.tmpl" ]]; then
        wt_template "$tmpl_dir/PROMPT.md.tmpl" "$wt_dir/ralph_${name}_PROMPT.md"
        ((scaffolded++))
    fi

    # Plan
    if [[ -f "$tmpl_dir/plan.md.tmpl" ]]; then
        wt_template "$tmpl_dir/plan.md.tmpl" "$wt_dir/ralph_${name}_plan.md"
        ((scaffolded++))
    fi

    # Activity log
    if [[ -f "$tmpl_dir/activity.md.tmpl" ]]; then
        wt_template "$tmpl_dir/activity.md.tmpl" "$wt_dir/ralph_${name}_activity.md"
        ((scaffolded++))
    fi

    # CLAUDE.md
    if [[ -f "$tmpl_dir/CLAUDE.md.tmpl" ]]; then
        wt_template "$tmpl_dir/CLAUDE.md.tmpl" "$wt_dir/CLAUDE.md"
        ((scaffolded++))
    fi

    wt_ok "Scaffolded $scaffolded files from templates"

    # Summary
    echo
    echo "${BOLD}Worktree ready:${RESET}"
    echo "  Path:   $wt_dir"
    echo "  Branch: $branch_name"
    echo "  Base:   $base_branch"
    echo
    echo "Next steps:"
    echo "  1. Edit ${CYAN}ralph_${name}_plan.md${RESET} with your tasks"
    echo "  2. Edit ${CYAN}ralph_${name}_PROMPT.md${RESET} to customize the agent prompt"
    echo "  3. Run  ${GREEN}wt launch $name${RESET}"
}
