#!/usr/bin/env bash
# wt-status.sh — Dashboard of all worktrees and their progress

wt_status() {
    local show_hpc=false verbose=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hpc)     show_hpc=true; shift ;;
            -v|--verbose) verbose=true; shift ;;
            -h|--help)
                cat <<EOF
${BOLD}wt status${RESET} — Dashboard of worktrees, agent progress, and HPC jobs

${BOLD}USAGE${RESET}
    wt status [--hpc] [--verbose]

${BOLD}OPTIONS${RESET}
    --hpc       Also query HPC cluster for tagged jobs
    -v          Show file-level details per worktree
    -h, --help  Show this help
EOF
                return 0
                ;;
            *) wt_die "Unknown option: $1" ;;
        esac
    done

    wt_require_project
    wt_load_config

    local wt_dir_base
    wt_dir_base="$(wt_worktree_dir)"

    echo
    echo "${BOLD}Worktree Status — $(wt_cfg "project_name" "$(basename "$WT_ROOT")")${RESET}"
    echo "${DIM}$(printf '%.0s─' {1..60})${RESET}"

    # Parse git worktree list
    local worktree_count=0
    local line wt_path wt_branch

    while IFS= read -r line; do
        # Skip the main worktree
        wt_path="$(echo "$line" | awk '{print $1}')"
        wt_branch="$(echo "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')"

        # Only show wt/* branches (our managed worktrees)
        [[ "$wt_branch" == wt/* ]] || continue

        local name="${wt_branch#wt/}"
        ((worktree_count++))

        # Check if running
        local status_icon="${YELLOW}idle${RESET}"
        local pid_file="$WT_ROOT/.wt/pids/${name}.pid"
        if [[ -f "$pid_file" ]]; then
            local pid
            pid="$(<"$pid_file")"
            if kill -0 "$pid" 2>/dev/null; then
                status_icon="${GREEN}running${RESET} (PID $pid)"
            else
                status_icon="${DIM}stopped${RESET}"
                rm -f "$pid_file"
            fi
        fi

        # Parse plan.md for task progress
        local plan_file="$wt_path/ralph_${name}_plan.md"
        local total=0 done=0 progress_str="${DIM}no plan${RESET}"

        if [[ -f "$plan_file" ]]; then
            # Count tasks: look for "passes": true/false patterns
            total=$(grep -c '"passes"' "$plan_file" 2>/dev/null || true)
            done=$(grep -c '"passes":[[:space:]]*true' "$plan_file" 2>/dev/null || true)
            if [[ $total -gt 0 ]]; then
                local pct=$(( done * 100 / total ))
                local bar_filled=$(( pct / 5 ))
                local bar_empty=$(( 20 - bar_filled ))
                local bar="${GREEN}$(printf '%.0s█' $(seq 1 $bar_filled 2>/dev/null) )${DIM}$(printf '%.0s░' $(seq 1 $bar_empty 2>/dev/null) )${RESET}"
                progress_str="$bar ${done}/${total} (${pct}%)"
            fi
        fi

        # Branch ahead/behind
        local ahead_behind=""
        local base_branch
        base_branch="$(wt_cfg "project_base_branch" "main")"
        local counts
        counts="$(git -C "$WT_ROOT" rev-list --left-right --count "${base_branch}...${wt_branch}" 2>/dev/null || echo "0	0")"
        local behind ahead
        behind="$(echo "$counts" | cut -f1)"
        ahead="$(echo "$counts" | cut -f2)"
        if [[ "$ahead" -gt 0 || "$behind" -gt 0 ]]; then
            ahead_behind=" ${DIM}↑${ahead} ↓${behind}${RESET}"
        fi

        # Render
        echo
        printf "  ${BOLD}%-20s${RESET} %s%s\n" "$name" "$status_icon" "$ahead_behind"
        printf "  ${DIM}%-20s${RESET} %s\n" "" "$progress_str"

        if $verbose; then
            printf "  ${DIM}%-20s${RESET} %s\n" "path" "$wt_path"
            printf "  ${DIM}%-20s${RESET} %s\n" "branch" "$wt_branch"

            # Last commit
            local last_commit
            last_commit="$(git -C "$wt_path" log -1 --format='%h %s (%ar)' 2>/dev/null || echo 'no commits')"
            printf "  ${DIM}%-20s${RESET} %s\n" "last commit" "$last_commit"
        fi

    done < <(git -C "$WT_ROOT" worktree list)

    if [[ $worktree_count -eq 0 ]]; then
        echo "  ${DIM}No active worktrees. Create one with: wt create <name>${RESET}"
    fi

    echo
    echo "${DIM}$(printf '%.0s─' {1..60})${RESET}"
    echo "${DIM}$worktree_count worktree(s) | base: $(wt_cfg "project_base_branch" "main")${RESET}"

    # HPC jobs
    if $show_hpc; then
        echo
        wt_hpc_status_inline
    fi
}

# Inline HPC query for status dashboard
wt_hpc_status_inline() {
    local host user
    host="$(wt_cfg "hpc_host" "")"
    user="$(wt_cfg "hpc_user" "")"

    if [[ -z "$host" || -z "$user" ]]; then
        echo "${DIM}HPC: not configured (set [hpc] in .wt/config.toml)${RESET}"
        return 0
    fi

    echo "${BOLD}HPC Jobs (${host})${RESET}"
    ssh -o ConnectTimeout=5 "${user}@${host}" \
        "squeue -u ${user} --format='%.8i %.20j %.8T %.10M %.20S %.30Z' 2>/dev/null | head -20" \
        2>/dev/null || echo "  ${DIM}Could not connect to ${host}${RESET}"
}
