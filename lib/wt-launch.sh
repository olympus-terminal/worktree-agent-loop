#!/usr/bin/env bash
# wt-launch.sh — Launch ralph loop in a worktree

wt_launch() {
    local name="" iterations="" background=false resume=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bg)      background=true; shift ;;
            --resume)  resume=true; shift ;;
            -h|--help)
                cat <<EOF
${BOLD}wt launch${RESET} — Launch ralph loop in a worktree

${BOLD}USAGE${RESET}
    wt launch <name> [iterations] [--bg] [--resume]

Runs the ralph loop script for the given worktree.

${BOLD}ARGUMENTS${RESET}
    <name>          Worktree name
    [iterations]    Number of loop iterations (default: from config)

${BOLD}OPTIONS${RESET}
    --bg            Run in background with nohup
    --resume        Resume from last iteration (don't reset counter)
    -h, --help      Show this help
EOF
                return 0
                ;;
            -*)  wt_die "Unknown option: $1" ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$iterations" ]]; then
                    iterations="$1"
                else
                    wt_die "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    [[ -n "$name" ]] || wt_die "Usage: wt launch <name> [iterations] [--bg]"

    wt_require_project
    wt_load_config

    iterations="${iterations:-$(wt_cfg "agent_max_iterations" "20")}"
    local wt_dir
    wt_dir="$(wt_worktree_path "$name")"

    # Pre-flight checks
    [[ -d "$wt_dir" ]] || wt_die "Worktree not found: $wt_dir"

    local ralph_script="$wt_dir/ralph_${name}.sh"
    [[ -f "$ralph_script" ]] || wt_die "Ralph script not found: $ralph_script"
    [[ -x "$ralph_script" ]] || chmod +x "$ralph_script"

    local plan_file="$wt_dir/ralph_${name}_plan.md"
    [[ -f "$plan_file" ]] || wt_warn "Plan file not found: $plan_file"

    local prompt_file="$wt_dir/ralph_${name}_PROMPT.md"
    [[ -f "$prompt_file" ]] || wt_warn "Prompt file not found: $prompt_file"

    # Check for already-running instance
    local pid_file="$WT_ROOT/.wt/pids/${name}.pid"
    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid="$(<"$pid_file")"
        if kill -0 "$old_pid" 2>/dev/null; then
            wt_die "Ralph loop already running for '$name' (PID $old_pid). Kill it first or wait."
        else
            rm -f "$pid_file"
        fi
    fi

    local branch_name="wt/$name"
    local current_branch
    current_branch="$(wt_current_branch "$wt_dir")"
    if [[ "$current_branch" != "$branch_name" ]]; then
        wt_warn "Expected branch '$branch_name', but worktree is on '$current_branch'"
    fi

    wt_info "Launching ralph loop: $name ($iterations iterations)"

    local log_file="$WT_ROOT/.wt/logs/${name}_$(wt_timestamp).log"

    if $background; then
        nohup bash "$ralph_script" "$iterations" > "$log_file" 2>&1 &
        local pid=$!
        echo "$pid" > "$pid_file"
        wt_ok "Background launch: PID $pid"
        wt_ok "Log: $log_file"
        wt_ok "Stop: kill $pid"
    else
        wt_info "Log: $log_file"
        bash "$ralph_script" "$iterations" 2>&1 | tee "$log_file"
        local exit_code=${PIPESTATUS[0]}
        rm -f "$pid_file"
        if [[ $exit_code -eq 0 ]]; then
            wt_ok "Ralph loop completed successfully"
        else
            wt_error "Ralph loop exited with code $exit_code"
            return $exit_code
        fi
    fi
}
