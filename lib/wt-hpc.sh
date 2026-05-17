#!/usr/bin/env bash
# wt-hpc.sh — Query HPC jobs tagged to worktrees

wt_hpc() {
    local worktree="" all=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --worktree|-w) worktree="$2"; all=false; shift 2 ;;
            -h|--help)
                cat <<EOF
${BOLD}wt hpc${RESET} — Query HPC jobs tagged to worktrees

${BOLD}USAGE${RESET}
    wt hpc [--worktree <name>]

Queries the HPC cluster for SLURM jobs tagged with wt/* comments.

${BOLD}OPTIONS${RESET}
    -w, --worktree <name>   Filter to specific worktree's jobs
    -h, --help              Show this help

${BOLD}REQUIREMENTS${RESET}
    Configure [hpc] section in .wt/config.toml with host, user.
    Jobs must use --comment=wt/<name> in sbatch headers.
EOF
                return 0
                ;;
            *) wt_die "Unknown option: $1" ;;
        esac
    done

    wt_require_project
    wt_load_config

    local host user
    host="$(wt_cfg "hpc_host" "")"
    user="$(wt_cfg "hpc_user" "")"

    [[ -n "$host" ]] || wt_die "HPC host not configured. Set [hpc] host in .wt/config.toml"
    [[ -n "$user" ]] || wt_die "HPC user not configured. Set [hpc] user in .wt/config.toml"

    local filter_comment=""
    if [[ -n "$worktree" ]]; then
        filter_comment="wt/${worktree}"
        wt_info "Querying jobs for worktree: $worktree"
    else
        filter_comment="wt/"
        wt_info "Querying all wt-tagged jobs"
    fi

    echo

    # Query squeue for tagged jobs
    local squeue_cmd="squeue -u ${user} --format='%.10i %.25j %.8T %.12M %.20S %.50Z' 2>/dev/null"

    local result
    result="$(ssh -o ConnectTimeout=10 -o BatchMode=yes "${user}@${host}" "$squeue_cmd" 2>/dev/null)" || {
        wt_die "Could not connect to ${host}. Check SSH config and connectivity."
    }

    if [[ -z "$result" ]]; then
        echo "  ${DIM}No jobs found${RESET}"
        return 0
    fi

    # Filter for wt-tagged jobs (comment field shows in job name or we use sacct)
    echo "${BOLD}SLURM Jobs (${user}@${host})${RESET}"
    echo "${DIM}$(printf '%.0s─' {1..70})${RESET}"
    echo "$result"
    echo "${DIM}$(printf '%.0s─' {1..70})${RESET}"

    # Also check recent completed jobs
    echo
    echo "${BOLD}Recent completed jobs (last 24h):${RESET}"
    local sacct_cmd="sacct -u ${user} --starttime=now-1day --format=JobID,JobName%30,State,Elapsed,ExitCode --noheader 2>/dev/null | head -20"

    ssh -o ConnectTimeout=10 -o BatchMode=yes "${user}@${host}" "$sacct_cmd" 2>/dev/null || {
        echo "  ${DIM}Could not query job history${RESET}"
    }
}
