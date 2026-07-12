#!/bin/bash
# p-ralph: install custom merge drivers into the current repo.
#
# Registers three things in the current repo:
#   1. merge.pralphplan.driver     → merges plan files by OR of passes flags
#   2. merge.pralphactivity.driver → merges activity logs by section union
#   3. merge=ours for configured build artifacts (so verify-compile output
#      doesn't block merges)
#
# The driver scripts themselves live in the p-ralph install tree; this
# script just registers them with `git config` and writes
# `.git/info/attributes` mapping the plan/activity file names to the drivers.
#
# Usage:
#   install_merge_drivers.sh <plan_file> <activity_file> [<build_artifact>...]
#
# Idempotent; safe to re-run.
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <plan_file> <activity_file> [<build_artifact>...]" >&2
    exit 2
fi

PLAN_FILE="$1"; shift
ACTIVITY_FILE="$1"; shift
BUILD_ARTIFACTS=("$@")

if [ ! -d .git ]; then
    echo "error: must be run from the root of a git repo" >&2
    exit 1
fi

# Resolve the p-ralph lib dir relative to this script.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_DRIVER="${LIB_DIR}/merge_drivers/plan.py"
ACTIVITY_DRIVER="${LIB_DIR}/merge_drivers/activity.py"

chmod +x "$PLAN_DRIVER" "$ACTIVITY_DRIVER"

git config merge.pralphplan.name       "p-ralph plan OR-merge"
git config merge.pralphplan.driver     "${PLAN_DRIVER} %O %A %B"
git config merge.pralphactivity.name   "p-ralph activity section union"
git config merge.pralphactivity.driver "${ACTIVITY_DRIVER} %O %A %B"

mkdir -p .git/info
ATTR_FILE=".git/info/attributes"

# Keep p-ralph's rules in a replaceable block so repeated installs can update
# them without deleting attributes configured by the repository owner or other
# tools. Write to a sibling temporary file and rename it only after the
# existing file has been parsed successfully.
ATTR_BEGIN="# BEGIN p-ralph managed merge attributes"
ATTR_END="# END p-ralph managed merge attributes"
ATTR_TMP=$(mktemp "${ATTR_FILE}.p-ralph.XXXXXX")
trap 'rm -f -- "$ATTR_TMP"' EXIT

if [ -f "$ATTR_FILE" ]; then
    if ! awk -v begin="$ATTR_BEGIN" -v end="$ATTR_END" '
        $0 == begin {
            if (managed) exit 2
            managed = 1
            next
        }
        $0 == end {
            if (!managed) exit 3
            managed = 0
            next
        }
        !managed { print }
        END {
            if (managed) exit 4
        }
    ' "$ATTR_FILE" > "$ATTR_TMP"; then
        echo "error: malformed p-ralph block in ${ATTR_FILE}; file left unchanged" >&2
        exit 1
    fi
fi

if [ -s "$ATTR_TMP" ] && [ -n "$(tail -n 1 "$ATTR_TMP")" ]; then
    printf '\n' >> "$ATTR_TMP"
fi
{
    printf '%s\n' "$ATTR_BEGIN"
    printf '%s     merge=pralphplan\n' "$PLAN_FILE"
    printf '%s merge=pralphactivity\n' "$ACTIVITY_FILE"
    for a in "${BUILD_ARTIFACTS[@]}"; do
        printf '%s merge=ours\n' "$a"
    done
    printf '%s\n' "$ATTR_END"
} >> "$ATTR_TMP"

mv -- "$ATTR_TMP" "$ATTR_FILE"
trap - EXIT

echo "[p-ralph] merge drivers installed:"
echo "  plan:     ${PLAN_FILE} → pralphplan"
echo "  activity: ${ACTIVITY_FILE} → pralphactivity"
for a in "${BUILD_ARTIFACTS[@]}"; do
    echo "  ours:     ${a}"
done
