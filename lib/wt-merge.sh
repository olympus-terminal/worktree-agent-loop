#!/usr/bin/env bash
# wt-merge.sh — Merge worktree branch back (LaTeX-aware)

wt_merge() {
    local name="" target="" no_split=false dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --into)      target="$2"; shift 2 ;;
            --no-split)  no_split=true; shift ;;
            --dry-run)   dry_run=true; shift ;;
            -h|--help)
                cat <<EOF
${BOLD}wt merge${RESET} — Merge worktree branch back (LaTeX-aware)

${BOLD}USAGE${RESET}
    wt merge <name> [--into <branch>] [--no-split] [--dry-run]

Merges the wt/<name> branch into the target branch. On conflict in
.tex files, uses section-level splitting for finer-grained resolution.

${BOLD}ARGUMENTS${RESET}
    <name>            Worktree name to merge

${BOLD}OPTIONS${RESET}
    --into <branch>   Target branch (default: from config or main)
    --no-split        Skip LaTeX section-split conflict resolution
    --dry-run         Show what would happen without merging
    -h, --help        Show this help

${BOLD}MERGE STRATEGY${RESET}
    1. Attempt git merge --no-ff
    2. If .tex conflicts arise, run section-split on conflicted files
    3. Generate conflict report for human review
    4. User resolves remaining conflicts and commits
EOF
                return 0
                ;;
            -*)  wt_die "Unknown option: $1" ;;
            *)   name="$1"; shift ;;
        esac
    done

    [[ -n "$name" ]] || wt_die "Usage: wt merge <name> [--into <branch>]"

    wt_require_project
    wt_load_config

    local branch_name="wt/$name"
    target="${target:-$(wt_cfg "project_base_branch" "main")}"

    # Validate
    wt_branch_exists "$branch_name" || wt_die "Branch '$branch_name' does not exist."
    wt_branch_exists "$target" || wt_die "Target branch '$target' does not exist."

    # Check for running agent
    local pid_file="$WT_ROOT/.wt/pids/${name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid="$(<"$pid_file")"
        if kill -0 "$pid" 2>/dev/null; then
            wt_die "Agent is still running for '$name' (PID $pid). Stop it before merging."
        fi
    fi

    # Show what we'll merge
    local ahead behind counts
    counts="$(git -C "$WT_ROOT" rev-list --left-right --count "${target}...${branch_name}")"
    behind="$(echo "$counts" | cut -f1)"
    ahead="$(echo "$counts" | cut -f2)"

    wt_info "Merging $branch_name into $target"
    echo "  Commits ahead:  $ahead"
    echo "  Commits behind: $behind"

    if [[ "$ahead" -eq 0 ]]; then
        wt_warn "Nothing to merge — $branch_name has no new commits over $target"
        return 0
    fi

    if $dry_run; then
        echo
        wt_info "Dry run — showing diff summary:"
        git -C "$WT_ROOT" diff --stat "${target}...${branch_name}"
        return 0
    fi

    # Ensure we're on the target branch in the main worktree
    local current
    current="$(wt_current_branch "$WT_ROOT")"
    if [[ "$current" != "$target" ]]; then
        wt_info "Switching main worktree to $target"
        git -C "$WT_ROOT" checkout "$target"
    fi

    # Attempt merge
    if git -C "$WT_ROOT" merge --no-ff "$branch_name" -m "Merge $branch_name into $target"; then
        wt_ok "Merge completed cleanly!"
        return 0
    fi

    # Merge had conflicts
    wt_warn "Merge conflicts detected"

    # Find conflicted .tex files
    local tex_conflicts=()
    local other_conflicts=()
    while IFS= read -r file; do
        if [[ "$file" == *.tex ]]; then
            tex_conflicts+=("$file")
        else
            other_conflicts+=("$file")
        fi
    done < <(git -C "$WT_ROOT" diff --name-only --diff-filter=U)

    if [[ ${#tex_conflicts[@]} -gt 0 ]] && ! $no_split; then
        wt_info "Running LaTeX section-split on ${#tex_conflicts[@]} conflicted .tex file(s)"

        local install_dir
        install_dir="$(wt_install_dir)"
        local conflict_tool="$install_dir/lib/latex-merge/conflict-report.py"

        if [[ -f "$conflict_tool" ]]; then
            for texfile in "${tex_conflicts[@]}"; do
                wt_info "Analyzing: $texfile"
                python3 "$conflict_tool" "$WT_ROOT/$texfile"
                echo
            done
        else
            wt_warn "conflict-report.py not found, showing raw conflicts"
        fi
    fi

    echo
    echo "${BOLD}Conflicted files:${RESET}"
    for f in "${tex_conflicts[@]}" "${other_conflicts[@]}"; do
        echo "  ${RED}$f${RESET}"
    done
    echo
    echo "Resolve conflicts, then:"
    echo "  git add <files>"
    echo "  git commit"
    echo
    echo "Or abort with:"
    echo "  git merge --abort"

    return 1
}
