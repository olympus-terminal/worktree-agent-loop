#!/usr/bin/env bash
# wt-destroy.sh — Remove worktree, optionally delete branch

wt_destroy() {
    local name="" delete_branch=false force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --delete-branch) delete_branch=true; shift ;;
            -f|--force)      force=true; shift ;;
            -h|--help)
                cat <<EOF
${BOLD}wt destroy${RESET} — Remove a worktree and optionally delete its branch

${BOLD}USAGE${RESET}
    wt destroy <name> [--delete-branch] [--force]

${BOLD}ARGUMENTS${RESET}
    <name>              Worktree name to remove

${BOLD}OPTIONS${RESET}
    --delete-branch     Also delete the wt/<name> branch
    -f, --force         Force removal even with uncommitted changes
    -h, --help          Show this help
EOF
                return 0
                ;;
            -*)  wt_die "Unknown option: $1" ;;
            *)   name="$1"; shift ;;
        esac
    done

    [[ -n "$name" ]] || wt_die "Usage: wt destroy <name> [--delete-branch]"

    wt_require_project
    wt_load_config

    local branch_name="wt/$name"
    local wt_dir
    wt_dir="$(wt_worktree_path "$name")"

    # Check for running agent
    local pid_file="$WT_ROOT/.wt/pids/${name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid="$(<"$pid_file")"
        if kill -0 "$pid" 2>/dev/null; then
            if ! $force; then
                wt_die "Agent still running for '$name' (PID $pid). Use --force or stop it first."
            fi
            wt_warn "Killing running agent (PID $pid)"
            kill "$pid" 2>/dev/null || true
            sleep 1
        fi
        rm -f "$pid_file"
    fi

    # Check for uncommitted work
    if [[ -d "$wt_dir" ]] && ! $force; then
        local dirty
        dirty="$(git -C "$wt_dir" status --porcelain 2>/dev/null | head -1)"
        if [[ -n "$dirty" ]]; then
            wt_warn "Worktree has uncommitted changes:"
            git -C "$wt_dir" status --short
            echo
            wt_confirm "Destroy anyway? Uncommitted changes will be lost." || return 1
        fi
    fi

    # Check for unmerged commits
    if $delete_branch && wt_branch_exists "$branch_name" && ! $force; then
        local base_branch
        base_branch="$(wt_cfg "project_base_branch" "main")"
        local unmerged
        unmerged="$(git -C "$WT_ROOT" rev-list --count "${base_branch}..${branch_name}" 2>/dev/null || echo 0)"
        if [[ "$unmerged" -gt 0 ]]; then
            wt_warn "Branch '$branch_name' has $unmerged unmerged commit(s)"
            wt_confirm "Delete branch with unmerged work?" || return 1
        fi
    fi

    # Remove worktree
    if [[ -d "$wt_dir" ]]; then
        wt_info "Removing worktree: $wt_dir"
        if $force; then
            git -C "$WT_ROOT" worktree remove --force "$wt_dir" 2>/dev/null || rm -rf "$wt_dir"
        else
            git -C "$WT_ROOT" worktree remove "$wt_dir"
        fi
        wt_ok "Worktree removed"
    else
        wt_warn "Worktree directory not found: $wt_dir"
    fi

    # Clean up log files
    rm -f "$WT_ROOT/.wt/logs/${name}_"*.log

    # Delete branch
    if $delete_branch; then
        if wt_branch_exists "$branch_name"; then
            wt_info "Deleting branch: $branch_name"
            if $force; then
                git -C "$WT_ROOT" branch -D "$branch_name"
            else
                git -C "$WT_ROOT" branch -d "$branch_name"
            fi
            wt_ok "Branch deleted"
        else
            wt_warn "Branch '$branch_name' not found"
        fi
    else
        wt_info "Branch '$branch_name' preserved. Delete later with: git branch -d $branch_name"
    fi

    # Prune worktree refs
    git -C "$WT_ROOT" worktree prune

    wt_ok "Destroyed worktree '$name'"
}
