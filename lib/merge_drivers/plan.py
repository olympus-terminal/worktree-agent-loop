#!/usr/bin/env python3
"""p-ralph plan merge driver.

Merges two versions of a plan file (a JSON list of tasks, each with at least
an `id` and a `passes` field) by task id, taking the logical OR of `passes`
flags and preferring non-empty scalar fields from either side.

Invocation (as configured by `git config merge.pralphplan.driver`):
    plan.py %O %A %B
where
  %O = ancestor file (unused — OR-merge is associative, ancestor-free)
  %A = "ours" — script overwrites this file with the merged result
  %B = "theirs"

Exits 0 on success. Non-zero exits leave the merge unresolved so git will
fall back to conflict-marker behavior.
"""
import json
import sys


SCALAR_FIELDS = ("description", "reviewer_concern", "category", "priority",
                 "notes", "subject")


def load(path):
    with open(path) as f:
        return json.load(f)


def merge(a, b):
    by_id = {t["id"]: dict(t) for t in a}
    for t in b:
        tid = t["id"]
        if tid not in by_id:
            by_id[tid] = dict(t)
            continue
        by_id[tid]["passes"] = (
            bool(by_id[tid].get("passes", False))
            or bool(t.get("passes", False))
        )
        for k in SCALAR_FIELDS:
            if k in t and t[k] and t[k] != by_id[tid].get(k):
                by_id[tid][k] = t[k]

    order_a = [t["id"] for t in a]
    seen = set(order_a)
    order_b = [t["id"] for t in b if t["id"] not in seen]
    return [by_id[i] for i in order_a + order_b]


def main():
    if len(sys.argv) < 4:
        sys.stderr.write("usage: plan.py %O %A %B\n")
        sys.exit(2)
    _, ours, theirs = sys.argv[1], sys.argv[2], sys.argv[3]
    A = load(ours)
    B = load(theirs)
    merged = merge(A, B)
    with open(ours, "w") as f:
        json.dump(merged, f, indent=2)
        f.write("\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
