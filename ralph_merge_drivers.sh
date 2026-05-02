#!/bin/bash
# ralph_merge_drivers.sh — registers git merge drivers so plan and
# activity files auto-merge across parallel task branches.
#
# Environment variables (set by ralph.sh or caller):
#   LOOP_NAME     — loop identifier (default: ralph)
#   PLAN_FILE     — plan filename (default: ${LOOP_NAME}_plan.md)
#   ACTIVITY_FILE — activity filename (default: ${LOOP_NAME}_activity.md)
#
# What it installs:
#   plan driver:     OR-merges 'passes' flags per task id
#   activity driver: appends unique dated task-completion entries
#
# Driver scripts live in .git/ (per-repo, not committed). Idempotent.

set -uo pipefail

LOOP_NAME="${LOOP_NAME:-ralph}"
PLAN_FILE="${PLAN_FILE:-${LOOP_NAME}_plan.md}"
ACTIVITY_FILE="${ACTIVITY_FILE:-${LOOP_NAME}_activity.md}"

DRIVER_NAME_PLAN="${LOOP_NAME}plan"
DRIVER_NAME_ACT="${LOOP_NAME}activity"

# ── Plan merge driver: OR-merge 'passes' flags per task id ──

cat > .git/ralph_merge_plan.py <<'PYEOF'
#!/usr/bin/env python3
"""Merge driver for plan files: OR-merge 'passes' flags per task id."""
import json, sys
ancestor, ours, theirs = sys.argv[1], sys.argv[2], sys.argv[3]

with open(ours) as f:  A = json.load(f)
with open(theirs) as f: B = json.load(f)

by_id = {t["id"]: dict(t) for t in A}
for t in B:
    tid = t["id"]
    if tid not in by_id:
        by_id[tid] = dict(t); continue
    by_id[tid]["passes"] = bool(by_id[tid].get("passes", False)) or bool(t.get("passes", False))
    for k in ("description", "reviewer_concern", "category", "priority", "notes"):
        if k in t and t[k] != by_id[tid].get(k):
            by_id[tid][k] = t[k]

order_a = [t["id"] for t in A]
order_b = [t["id"] for t in B if t["id"] not in set(order_a)]
merged = [by_id[i] for i in order_a + order_b]

with open(ours, "w") as f:
    json.dump(merged, f, indent=2); f.write("\n")
sys.exit(0)
PYEOF
chmod +x .git/ralph_merge_plan.py

# ── Activity merge driver: union of dated task-entry blocks ──

cat > .git/ralph_merge_activity.py <<'PYEOF'
#!/usr/bin/env python3
"""Merge driver for activity files: union of dated task-entry blocks."""
import re, sys
ancestor, ours, theirs = sys.argv[1], sys.argv[2], sys.argv[3]

with open(ours) as f:  O = f.read()
with open(theirs) as f: T = f.read()

ENTRY_RE = re.compile(
    r"(## \d{4}-\d{2}-\d{2} — Task (\d+) complete.*?)(?=\n## \d{4}-\d{2}-\d{2} — Task|\Z)",
    re.DOTALL)

def split(text):
    m = re.search(r"## Iteration log\s*\n", text)
    if m: return text[:m.end()], text[m.end():]
    first = ENTRY_RE.search(text)
    if first: return text[:first.start()], text[first.start():]
    return text, ""

def entries(body):
    out = {}
    for m in ENTRY_RE.finditer(body + "\n## 9999-99-99 — Task 9999 complete\nSENTINEL"):
        tid = int(m.group(2))
        if tid == 9999: continue
        out[tid] = m.group(1).rstrip() + "\n"
    return out

header_o, body_o = split(O)
_,        body_t = split(T)

merged = entries(body_o)
for tid, chunk in entries(body_t).items():
    if tid not in merged or len(chunk) > len(merged[tid]):
        merged[tid] = chunk

ordered = [merged[t] for t in sorted(merged)]
with open(ours, "w") as f:
    f.write(header_o.rstrip() + "\n\n" + "\n".join(ordered).rstrip() + "\n")
sys.exit(0)
PYEOF
chmod +x .git/ralph_merge_activity.py

# ── Register drivers in git config ──

git config "merge.${DRIVER_NAME_PLAN}.name"       "${LOOP_NAME} plan union"
git config "merge.${DRIVER_NAME_PLAN}.driver"      ".git/ralph_merge_plan.py %O %A %B"
git config "merge.${DRIVER_NAME_ACT}.name"         "${LOOP_NAME} activity concat"
git config "merge.${DRIVER_NAME_ACT}.driver"       ".git/ralph_merge_activity.py %O %A %B"

# ── Write .git/info/attributes ──

# Append rather than overwrite to preserve existing attributes
ATTR_FILE=".git/info/attributes"
mkdir -p .git/info

# Remove any existing lines for these files, then re-add
if [ -f "$ATTR_FILE" ]; then
    grep -v "^${PLAN_FILE}\|^${ACTIVITY_FILE}" "$ATTR_FILE" > "${ATTR_FILE}.tmp" 2>/dev/null || true
    mv "${ATTR_FILE}.tmp" "$ATTR_FILE"
fi

cat >> "$ATTR_FILE" <<ATTREOF
${PLAN_FILE}     merge=${DRIVER_NAME_PLAN}
${ACTIVITY_FILE} merge=${DRIVER_NAME_ACT}
ATTREOF

echo "[merge-drivers] installed ${DRIVER_NAME_PLAN} + ${DRIVER_NAME_ACT}"
