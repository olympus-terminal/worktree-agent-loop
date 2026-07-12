#!/bin/bash
# Integration regressions for the 2026-07-12 P0 safety fixes.
# All repositories and content created here are synthetic unit-test fixtures.

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent_${USER:-user}_XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

PASS_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok %d - %s\n' "$PASS_COUNT" "$1"
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

expect_build_failure() {
    local repo="$1"
    local mode="$2"
    local output="$3"
    local args_log="$4"
    local rc

    set +e
    (
        cd "$repo"
        FAKE_AGENT_MODE="$mode" FAKE_ARGS_LOG="$args_log" FAKE_TARGET_REPO="$repo" \
            bash "$SOURCE_ROOT/bin/p-ralph" build
    ) >"$output" 2>&1
    rc=$?
    set -e

    [ "$rc" -ne 0 ] || fail "expected build failure in $repo"
}

FAKE_AGENT="$TMP_ROOT/fake-agent"
cat > "$FAKE_AGENT" <<'FAKEEOF'
#!/bin/bash
set -euo pipefail

{
    printf 'argv:'
    printf ' <%s>' "$@"
    printf '\n'
} >> "$FAKE_ARGS_LOG"

FAKE_MODE="${FAKE_AGENT_MODE:-success}"
if [ "$FAKE_MODE" = "fail" ]; then
    echo "intentional fake-agent failure" >&2
    exit 17
fi

if [ "$FAKE_MODE" = "resolver_abort" ] && [ "${*:-}" != "${*%--allowedTools*}" ]; then
    git merge --abort
    echo "intentional fake-resolver abort" >&2
    exit 0
fi

printf 'task output\n' > result.txt
if [ "$FAKE_MODE" = "resolver_abort" ]; then
    printf 'task-side conflict\n' > conflict.txt
fi
sed -i 's/"passes": false/"passes": true/' testloop_plan.md
cat >> testloop_activity.md <<'EOF'

## 2026-07-12 — Task 1 complete

Synthetic integration-test task completed.
EOF
git add result.txt conflict.txt testloop_plan.md testloop_activity.md
if [ "$FAKE_MODE" != "no_commit" ]; then
    git commit -q -m "Complete synthetic task 1"
fi
if [ "$FAKE_MODE" = "resolver_abort" ]; then
    printf 'target-side conflict\n' > "$FAKE_TARGET_REPO/conflict.txt"
    git -C "$FAKE_TARGET_REPO" add conflict.txt
    git -C "$FAKE_TARGET_REPO" commit -q -m "Create synthetic target conflict"
fi
if [ "$FAKE_MODE" != "no_promise" ]; then
    echo '<promise>COMPLETE</promise>'
fi
FAKEEOF
chmod +x "$FAKE_AGENT"

make_repo() {
    local name="$1"
    local branch="$2"
    local verify_cmd="$3"
    local integrate_verify_cmd="$4"
    local repo="$TMP_ROOT/$name"

    mkdir -p "$repo"
    git -C "$repo" init -q -b "$branch"
    git -C "$repo" config user.name "p-ralph integration test"
    git -C "$repo" config user.email "integration-test@example.invalid"

    cat > "$repo/.p-ralph.yaml" <<EOF
loop_id: testloop
tag_suffix: -baseline
branch_prefix: "testloop/task"
plan_file: "testloop_plan.md"
activity_file: "testloop_activity.md"
build_artifacts: []
max_parallel: 1
worktree_dir: ".pralph-worktrees"
claude:
  binary: "$FAKE_AGENT"
  model: fake-model
  extra_flags: []
  resolver_allowed_tools: "Read,Edit,Write,Bash(git add:*),Bash(git commit:*),Bash(git status),Bash(git diff:*),Glob,Grep"
verify_cmd: "$verify_cmd"
integrate_verify_cmd: "$integrate_verify_cmd"
prompt_template: "testloop_PROMPT.md"
EOF
    cat > "$repo/testloop_plan.md" <<'EOF'
[
  {
    "id": 1,
    "description": "Synthetic integration-test task.",
    "passes": false
  }
]
EOF
    cat > "$repo/testloop_activity.md" <<'EOF'
# Synthetic test activity log

## Iteration log
EOF
    cat > "$repo/testloop_PROMPT.md" <<'EOF'
Complete synthetic test task {{TASK_ID}}, commit it, and exit.
EOF
    cat > "$repo/.gitignore" <<'EOF'
/.pralph-worktrees/
/testloop_logs/
EOF
    printf 'synthetic fixture\n' > "$repo/README.md"
    printf 'baseline conflict content\n' > "$repo/conflict.txt"
    cp "$SOURCE_ROOT/templates/loop.sh.tmpl" "$repo/testloop_loop.sh"
    chmod +x "$repo/testloop_loop.sh"

    git -C "$repo" add .
    git -C "$repo" commit -q -m "Create synthetic p-ralph fixture"
    printf '%s\n' "$repo"
}

# A non-zero agent exit must stop the run before integration.
repo=$(make_repo worker_failure trunk true true)
before=$(git -C "$repo" rev-parse HEAD)
expect_build_failure "$repo" fail "$TMP_ROOT/worker_failure.out" "$TMP_ROOT/worker_failure.args"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "worker failure changed target HEAD"
! grep -q 'Phase D:' "$TMP_ROOT/worker_failure.out" || fail "worker failure reached integration"
if ! grep -q 'worker failed with exit 17' "$TMP_ROOT/worker_failure.out"; then
    cat "$TMP_ROOT/worker_failure.out" >&2
    fail "worker status was not propagated"
fi
pass "agent failure propagates and skips integration"

# A zero-exit agent must still emit the documented completion marker.
repo=$(make_repo missing_promise trunk true true)
before=$(git -C "$repo" rev-parse HEAD)
expect_build_failure "$repo" no_promise "$TMP_ROOT/missing_promise.out" "$TMP_ROOT/missing_promise.args"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "missing promise changed target HEAD"
! grep -q 'Phase D:' "$TMP_ROOT/missing_promise.out" || fail "missing promise reached integration"
grep -q 'did not emit <promise>COMPLETE</promise>' "$repo"/testloop_logs/task1_*.log || fail "missing promise was not rejected"
pass "completion marker is required before verification and integration"

# A marker and passing verification cannot substitute for a worker commit.
repo=$(make_repo missing_commit trunk true true)
before=$(git -C "$repo" rev-parse HEAD)
expect_build_failure "$repo" no_commit "$TMP_ROOT/missing_commit.out" "$TMP_ROOT/missing_commit.args"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "missing commit changed target HEAD"
! grep -q 'Phase D:' "$TMP_ROOT/missing_commit.out" || fail "missing commit reached integration"
grep -q 'completed without a commit' "$repo"/testloop_logs/task1_*.log || fail "missing worker commit was not rejected"
pass "successful worker must create a task-branch commit"

# Per-task verification must run and block integration on failure.
repo=$(make_repo verify_failure trunk false true)
before=$(git -C "$repo" rev-parse HEAD)
expect_build_failure "$repo" success "$TMP_ROOT/verify_failure.out" "$TMP_ROOT/verify_failure.args"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "verify failure changed target HEAD"
! grep -q 'Phase D:' "$TMP_ROOT/verify_failure.out" || fail "verify failure reached integration"
grep -q 'verification failed' "$repo"/testloop_logs/task1_*.log || fail "per-task verification did not run"
pass "per-task verify failure blocks integration"

# An existing baseline must belong to the current target history.
repo=$(make_repo unrelated_baseline trunk true true)
before=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch -q -c unrelated-baseline
git -C "$repo" commit -q --allow-empty -m "Create unrelated baseline tip"
git -C "$repo" tag testloop-baseline
git -C "$repo" switch -q trunk
expect_build_failure "$repo" success "$TMP_ROOT/unrelated_baseline.out" "$TMP_ROOT/unrelated_baseline.args"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "unrelated baseline changed target HEAD"
grep -q 'is not an ancestor of trunk' "$TMP_ROOT/unrelated_baseline.out" || fail "unrelated baseline was not rejected"
! git -C "$repo" show-ref --verify --quiet refs/heads/testloop/task1 || fail "unrelated baseline created a task branch"
pass "existing baseline must be an ancestor of the target"

# Both untracked and tracked target changes must be refused before mutation.
repo=$(make_repo untracked_dirty trunk true true)
printf 'do not move me\n' > "$repo/untracked.txt"
expect_build_failure "$repo" success "$TMP_ROOT/untracked_dirty.out" "$TMP_ROOT/untracked_dirty.args"
grep -q 'target worktree is dirty' "$TMP_ROOT/untracked_dirty.out" || fail "untracked dirt was not reported"
grep -q '?? untracked.txt' "$TMP_ROOT/untracked_dirty.out" || fail "untracked path was not reported"
! git -C "$repo" rev-parse -q --verify refs/tags/testloop-baseline >/dev/null || fail "dirty run created baseline tag"

repo=$(make_repo tracked_dirty trunk true true)
printf 'tracked modification\n' >> "$repo/README.md"
expect_build_failure "$repo" success "$TMP_ROOT/tracked_dirty.out" "$TMP_ROOT/tracked_dirty.args"
grep -q ' M README.md' "$TMP_ROOT/tracked_dirty.out" || fail "tracked path was not reported"
! git -C "$repo" rev-parse -q --verify refs/tags/testloop-baseline >/dev/null || fail "dirty run created baseline tag"
pass "tracked and untracked target changes are refused before mutation"

# A merge failure must not fall through to integrated verification or success.
repo=$(make_repo merge_failure trunk true true)
cat > "$repo/.git/hooks/pre-merge-commit" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$repo/.git/hooks/pre-merge-commit"
before=$(git -C "$repo" rev-parse HEAD)
expect_build_failure "$repo" success "$TMP_ROOT/merge_failure.out" "$TMP_ROOT/merge_failure.args"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "failed merge changed target HEAD"
grep -q 'Phase D FAILED' "$TMP_ROOT/merge_failure.out" || fail "merge failure was not tracked"
! grep -q 'Phase E:' "$TMP_ROOT/merge_failure.out" || fail "merge failure reached integrated verification"
pass "merge failure exits nonzero before Phase E"

# An aborted resolver must be detected even after MERGE_HEAD disappears.
repo=$(make_repo resolver_abort trunk true true)
expect_build_failure "$repo" resolver_abort "$TMP_ROOT/resolver_abort.out" "$TMP_ROOT/resolver_abort.args"
grep -q 'branch was not integrated' "$TMP_ROOT/resolver_abort.out" || fail "aborted resolver was reported as successful"
grep -q 'Phase D FAILED' "$TMP_ROOT/resolver_abort.out" || fail "aborted resolver did not fail integration"
! grep -q 'Phase E:' "$TMP_ROOT/resolver_abort.out" || fail "aborted resolver reached integrated verification"
! git -C "$repo" merge-base --is-ancestor testloop/task1 trunk || fail "aborted resolver branch unexpectedly integrated"
! git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null || fail "aborted resolver left a merge in progress"
pass "aborted resolver cannot fall through as integration success"

# Reset must reject traversal outside the repository before deletion.
repo=$(make_repo reset_traversal trunk true true)
outside_guard="$TMP_ROOT/outside_guard"
mkdir -p "$outside_guard"
printf 'preserve me\n' > "$outside_guard/sentinel.txt"
sed -i 's|worktree_dir: ".pralph-worktrees"|worktree_dir: "../outside_guard"|' "$repo/.p-ralph.yaml"
git -C "$repo" add .p-ralph.yaml
git -C "$repo" commit -q -m "Configure malicious traversal fixture"
set +e
(
    cd "$repo"
    printf 'yes\n' | bash "$SOURCE_ROOT/bin/p-ralph" reset
) >"$TMP_ROOT/reset_traversal.out" 2>&1
reset_rc=$?
set -e
[ "$reset_rc" -ne 0 ] || fail "reset accepted traversal outside repository"
[ -f "$outside_guard/sentinel.txt" ] || fail "reset deleted outside sentinel"
grep -q 'worktree_dir resolves outside the repository root' "$TMP_ROOT/reset_traversal.out" || fail "reset traversal error missing"
pass "reset refuses worktree paths outside the repository"

# A repository with no main branch must integrate and report against its target.
repo=$(make_repo target_branch trunk 'test -f result.txt' 'test -f result.txt')
mkdir -p "$repo/.git/info"
printf '*.custom merge=custom\n' > "$repo/.git/info/attributes"
(
    cd "$repo"
    FAKE_AGENT_MODE=success FAKE_ARGS_LOG="$TMP_ROOT/target_branch.args" FAKE_TARGET_REPO="$repo" \
        bash "$SOURCE_ROOT/bin/p-ralph" build
) >"$TMP_ROOT/target_branch.out" 2>&1
[ "$(git -C "$repo" branch --show-current)" = "trunk" ] || fail "target branch changed"
git -C "$repo" show-ref --verify --quiet refs/heads/trunk || fail "trunk branch missing"
! git -C "$repo" show-ref --verify --quiet refs/heads/main || fail "test unexpectedly created main"
[ -f "$repo/result.txt" ] || fail "successful task was not integrated"
[ "$(git -C "$repo" log --merges --format='%s' -1)" = "p-ralph: merge task 1" ] || fail "task merge missing"
[ ! -e "$repo/.pralph-lib" ] || fail "build created an untracked library symlink"
grep -q 'running verify: test -f result.txt' "$repo"/testloop_logs/task1_*.log || fail "successful per-task verification was not logged"
(
    cd "$repo"
    bash "$SOURCE_ROOT/bin/p-ralph" status
) >"$TMP_ROOT/target_branch.status" 2>&1
grep -q '^target:   trunk$' "$TMP_ROOT/target_branch.status" || fail "status did not identify trunk target"
grep -q 'ahead of trunk, merged' "$TMP_ROOT/target_branch.status" || fail "status used the wrong comparison branch"
pass "current non-main target branch is used consistently"

# Merge-driver installation must preserve unrelated local attributes and remain
# idempotent when it refreshes its own managed block.
grep -Fxq '*.custom merge=custom' "$repo/.git/info/attributes" || fail "merge-driver install deleted an existing attribute"
(
    cd "$repo"
    bash "$SOURCE_ROOT/lib/install_merge_drivers.sh" \
        testloop_plan.md testloop_activity.md >/dev/null
)
grep -Fxq '*.custom merge=custom' "$repo/.git/info/attributes" || fail "merge-driver reinstall deleted an existing attribute"
[ "$(grep -Fxc '# BEGIN p-ralph managed merge attributes' "$repo/.git/info/attributes")" -eq 1 ] || fail "merge-driver reinstall duplicated its managed block"
grep -Eq '^testloop_plan\.md[[:space:]]+merge=pralphplan$' "$repo/.git/info/attributes" || fail "plan merge attribute missing"
grep -Eq '^testloop_activity\.md[[:space:]]+merge=pralphactivity$' "$repo/.git/info/attributes" || fail "activity merge attribute missing"
pass "merge-driver install preserves existing attributes and is idempotent"

# Safe defaults and canonical installation instructions must remain regression-tested.
for file in \
    "$SOURCE_ROOT/templates/.p-ralph.yaml.tmpl" \
    "$SOURCE_ROOT/examples/python-package.yaml" \
    "$SOURCE_ROOT/examples/manuscript.yaml" \
    "$SOURCE_ROOT/lib/resolve_with_claude.sh"; do
    ! grep -q -- '--dangerously-skip-permissions' "$file" || fail "permission bypass remains in $file"
done
! grep -q -- '--dangerously-skip-permissions' "$TMP_ROOT/target_branch.args" || fail "worker received a permission bypass"
grep -q 'https://github.com/olympus-terminal/worktree-agent-loop.git' "$SOURCE_ROOT/README.md" || fail "canonical clone URL missing"
! grep -q 'https://github.com/olympus-terminal/p-ralph.git' "$SOURCE_ROOT/README.md" || fail "nonexistent clone URL remains"
pass "safe permission defaults and canonical clone URL are present"

for file in \
    "$SOURCE_ROOT/docs/legacy/RALPH-howto.txt" \
    "$SOURCE_ROOT/docs/legacy/RALPH_WIGGUM_MASTER_GUIDE.md" \
    "$SOURCE_ROOT/docs/legacy/ralph_playbook_claytonfarr.txt"; do
    head -n 12 "$file" | grep -Eiq 'outdated.*unsafe|unsafe.*outdated' || fail "legacy warning missing from $file"
done
pass "legacy guides prominently warn against outdated unsafe commands"

printf '1..%d\n' "$PASS_COUNT"
