#!/usr/bin/env bash
# wt-init.sh — Initialize current repo for worktree workflow

wt_init() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            -h|--help)
                cat <<EOF
${BOLD}wt init${RESET} — Initialize current repo for worktree workflow

${BOLD}USAGE${RESET}
    wt init [--force]

Creates .wt/ directory with config template, sets up .gitattributes
for LaTeX-aware merging, and adds transient dirs to .gitignore.

${BOLD}OPTIONS${RESET}
    -f, --force    Reinitialize even if .wt/ exists
    -h, --help     Show this help
EOF
                return 0
                ;;
            *) wt_die "Unknown option: $1" ;;
        esac
    done

    # Must be in a git repo
    git rev-parse --git-dir &>/dev/null || wt_die "Not a git repository."

    local root
    root="$(git rev-parse --show-toplevel)"

    if [[ -d "$root/.wt" ]] && ! $force; then
        wt_die "Already initialized (.wt/ exists). Use --force to reinitialize."
    fi

    wt_info "Initializing wt project in $root"

    # Create .wt structure
    mkdir -p "$root/.wt"/{pids,logs}

    # Create default config if none exists
    if [[ ! -f "$root/.wt/config.toml" ]]; then
        local project_name
        project_name="$(basename "$root")"
        cat > "$root/.wt/config.toml" <<TOML
[project]
name = "$project_name"
base_branch = "main"
worktree_dir = "../worktrees"

[agent]
model = "opus"
max_iterations = 20
# tool_allowlist = "Bash,Read,Write,Edit,Glob,Grep"

[hpc]
# host = "cluster.example.edu"
# user = "username"
# scratch = "/scratch/username"
# conda_env = "myenv"
# partition = "default"

[latex]
compiler = "tectonic"
main_file = "main.tex"
section_pattern = '\\\\section\*?\{.*?\}'
TOML
        wt_ok "Created .wt/config.toml — edit with your project settings"
    fi

    # Set up .gitattributes for LaTeX-aware merging
    local gitattr="$root/.gitattributes"
    local needs_update=true

    if [[ -f "$gitattr" ]] && grep -q 'merge=union' "$gitattr"; then
        needs_update=false
    fi

    if $needs_update; then
        {
            echo ""
            echo "# wt: LaTeX-aware merge strategies"
            echo "*.bib merge=union"
            echo "*.bbl merge=union"
        } >> "$gitattr"
        wt_ok "Updated .gitattributes — .bib/.bbl use union merge"
    fi

    # Add transient dirs to .gitignore
    local gitignore="$root/.gitignore"
    local wt_ignores=".wt/pids/
.wt/logs/"

    for pattern in ".wt/pids/" ".wt/logs/"; do
        if ! grep -qF "$pattern" "$gitignore" 2>/dev/null; then
            echo "$pattern" >> "$gitignore"
        fi
    done

    wt_ok "Project initialized. Next: edit .wt/config.toml, then 'wt create <name>'"
}
