#!/bin/bash
# p-ralph: invoke Claude to resolve an in-progress merge conflict.
#
# Called by the loop runner when the merge drivers can't handle a
# conflict — typically real source-file overlaps between two tasks.
#
# Usage:
#   resolve_with_claude.sh <task_id> <config_path>
#
# Preconditions: the repo is mid-merge (MERGE_HEAD exists) with
# unmerged paths in the working tree. The resolver must finalize the
# merge with `git commit --no-edit` or leave it for the caller to abort.
#
# The resolver is explicitly forbidden from `git merge --abort` or
# `git reset` — those were the silent failure modes that motivated
# this tool.

set -uo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <task_id> <config_path>" >&2
    exit 2
fi

TASK_ID="$1"
CONFIG="$2"

read_cfg() {
    python3 - "$CONFIG" "$1" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)
path = sys.argv[2].split(".")
v = cfg
for p in path:
    if isinstance(v, dict):
        v = v.get(p)
    else:
        v = None
        break
print(v or "")
PYEOF
}

CLAUDE_BIN=$(read_cfg claude.binary)
CLAUDE_MODEL=$(read_cfg claude.model)
ALLOWED=$(read_cfg claude.resolver_allowed_tools)
VERIFY_CMD=$(read_cfg verify_cmd)
BRANCH_PREFIX=$(read_cfg branch_prefix)

UNMERGED=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
if [ -z "${UNMERGED// /}" ]; then
    echo "[resolver] no unmerged paths; nothing to do"
    exit 0
fi

PROMPT=$(mktemp)
trap 'rm -f "$PROMPT"' EXIT

cat > "$PROMPT" <<PROMPTEOF
# Resolve merge conflicts for ${BRANCH_PREFIX}${TASK_ID}

You are resolving a git merge conflict. The repository is mid-merge; these
files contain \`<<<<<<< HEAD\`, \`=======\`, \`>>>>>>> ${BRANCH_PREFIX}${TASK_ID}\`
conflict markers:

${UNMERGED}

## Your job

1. Run \`git status\` to see unmerged paths.
2. For EACH unmerged file:
   - Read the file
   - Find all conflict regions
   - Resolve by **keeping both contributions** wherever they are additive.
     When the two sides edit the same sentence with slightly different wording,
     prefer the version with the more precise numerical statement (if any).
   - Remove all \`<<<<<<<\`, \`=======\`, \`>>>>>>>\` markers.
3. Run: \`${VERIFY_CMD}\`
   It must succeed. Fix any errors you introduced.
4. Stage the resolved files: \`git add <file>...\`
5. Complete the merge: \`git commit --no-edit\`
   Do NOT start a new commit; this must finalize the in-progress merge.
6. Output \`<promise>COMPLETE</promise>\`.

## Hard rules

- Do NOT abort the merge.
- Do NOT edit files that are not listed as unmerged.
- Do NOT fabricate content. If you cannot tell which side is correct,
  keep both as adjacent paragraphs/statements.
- Never use \`git merge --abort\` or \`git reset\`.
PROMPTEOF

"$CLAUDE_BIN" --model "$CLAUDE_MODEL" \
    -p "$(cat "$PROMPT")" \
    --output-format text \
    --allowedTools "$ALLOWED" || true
