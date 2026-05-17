#!/usr/bin/env bash
# common.sh — Shared utilities for wt commands
# Sourced by bin/wt before dispatching to subcommands.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'  GREEN=$'\033[0;32m'  YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m' CYAN=$'\033[0;36m'   BOLD=$'\033[1m'
    DIM=$'\033[2m'     RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

# ── Logging ───────────────────────────────────────────────────────────
wt_log()   { printf '%s %s[wt]%s %s\n' "$(date +%H:%M:%S)" "$DIM" "$RESET" "$*"; }
wt_info()  { printf '%s %s[wt]%s %s\n' "$(date +%H:%M:%S)" "$CYAN" "$RESET" "$*"; }
wt_ok()    { printf '%s %s[wt]%s %s\n' "$(date +%H:%M:%S)" "$GREEN" "$RESET" "$*"; }
wt_warn()  { printf '%s %s[wt]%s %s%s%s\n' "$(date +%H:%M:%S)" "$YELLOW" "$RESET" "$YELLOW" "$*" "$RESET" >&2; }
wt_error() { printf '%s %s[wt]%s %s%s%s\n' "$(date +%H:%M:%S)" "$RED" "$RESET" "$RED" "$*" "$RESET" >&2; }
wt_die()   { wt_error "$@"; exit 1; }

# ── Project root discovery ────────────────────────────────────────────
# Walk up from cwd looking for .wt/ directory
wt_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.wt" ]]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Require that we're inside a wt-initialized project
wt_require_project() {
    WT_ROOT="$(wt_project_root)" || wt_die "Not inside a wt project (no .wt/ found). Run 'wt init' first."
    export WT_ROOT
}

# ── TOML config parsing ──────────────────────────────────────────────
# Minimal bash TOML parser — handles [section], key = "value", key = value
# Produces variables like: WT_CFG_section_key="value"
declare -A WT_CFG

wt_load_config() {
    local config_file="${1:-$WT_ROOT/.wt/config.toml}"
    [[ -f "$config_file" ]] || wt_die "Config not found: $config_file"

    local section=""
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip comments and trailing whitespace
        line="${line%%#*}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        # Section header
        if [[ "$line" =~ ^\[([a-zA-Z0-9_.-]+)\]$ ]]; then
            section="${BASH_REMATCH[1]//./_}"
            continue
        fi

        # Key = value
        if [[ "$line" =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Strip surrounding quotes
            if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            if [[ -n "$section" ]]; then
                WT_CFG["${section}_${key}"]="$value"
            else
                WT_CFG["$key"]="$value"
            fi
        fi
    done < "$config_file"
}

# Get a config value with optional default
wt_cfg() {
    local key="$1"
    local default="${2:-}"
    printf '%s' "${WT_CFG[$key]:-$default}"
}

# ── Worktree path resolution ─────────────────────────────────────────
wt_worktree_dir() {
    local base
    base="$(wt_cfg "project_worktree_dir" "../worktrees")"
    # Resolve relative to project root
    if [[ "$base" != /* ]]; then
        base="$WT_ROOT/$base"
    fi
    printf '%s' "$base"
}

wt_worktree_path() {
    local name="$1"
    printf '%s/%s' "$(wt_worktree_dir)" "$name"
}

# ── Template substitution ────────────────────────────────────────────
# Replace {{VAR}} placeholders with values from an associative array
# Usage: wt_template <template_file> <output_file>
# Set WT_TMPL[VAR]=value before calling
declare -A WT_TMPL

wt_template() {
    local template="$1"
    local output="$2"

    [[ -f "$template" ]] || wt_die "Template not found: $template"

    local content
    content="$(<"$template")"

    local var
    for var in "${!WT_TMPL[@]}"; do
        content="${content//\{\{$var\}\}/${WT_TMPL[$var]}}"
    done

    printf '%s\n' "$content" > "$output"
}

# ── Git helpers ───────────────────────────────────────────────────────
wt_current_branch() {
    git -C "${1:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null
}

wt_branch_exists() {
    git -C "$WT_ROOT" rev-parse --verify "$1" &>/dev/null
}

wt_worktree_exists() {
    local name="$1"
    local wt_path
    wt_path="$(wt_worktree_path "$name")"
    git -C "$WT_ROOT" worktree list --porcelain | grep -q "^worktree ${wt_path}$"
}

# ── Misc ──────────────────────────────────────────────────────────────
wt_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

wt_confirm() {
    local prompt="${1:-Continue?}"
    printf '%s [y/N] ' "$prompt"
    local reply
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# Find the wt install directory (where templates etc. live)
wt_install_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # lib/ -> parent
    printf '%s' "$(dirname "$script_dir")"
}
