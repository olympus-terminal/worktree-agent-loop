#!/usr/bin/env python3
"""p-ralph activity-log merge driver.

Merges two versions of an activity file (markdown, with one section per
completed task under a header like "## YYYY-MM-DD — Task N complete") by:

  1. Keeping the header block of "ours" (everything before the first task
     section, or before "## Iteration log" if present).
  2. Parsing task sections from both sides, keyed by integer task id.
  3. Union: if both sides have the same task id, keep the longer section
     (longer ≈ more detail survived a later edit).
  4. Emitting sections in task-id order after the header.

Invocation (as configured by `git config merge.pralphactivity.driver`):
    activity.py %O %A %B
"""
import re
import sys


HEADER_SPLIT_RE = re.compile(r"## Iteration log\s*\n")
ENTRY_RE = re.compile(
    r"(## \d{4}-\d{2}-\d{2} — Task (\d+) complete.*?)"
    r"(?=\n## \d{4}-\d{2}-\d{2} — Task|\Z)",
    re.DOTALL,
)


def load(path):
    with open(path) as f:
        return f.read()


def split_header(text):
    m = HEADER_SPLIT_RE.search(text)
    if m:
        return text[:m.end()], text[m.end():]
    first = ENTRY_RE.search(text)
    if first:
        return text[:first.start()], text[first.start():]
    return text, ""


def entries(body):
    out = {}
    # Sentinel terminator lets the regex capture the final real entry cleanly.
    sentinel = "\n## 9999-99-99 — Task 9999 complete\nSENTINEL"
    for m in ENTRY_RE.finditer(body + sentinel):
        tid = int(m.group(2))
        if tid == 9999:
            continue
        out[tid] = m.group(1).rstrip() + "\n"
    return out


def main():
    if len(sys.argv) < 4:
        sys.stderr.write("usage: activity.py %O %A %B\n")
        sys.exit(2)
    _, ours_path, theirs_path = sys.argv[1], sys.argv[2], sys.argv[3]

    O = load(ours_path)
    T = load(theirs_path)

    header_o, body_o = split_header(O)
    _, body_t = split_header(T)

    merged = entries(body_o)
    for tid, chunk in entries(body_t).items():
        if tid not in merged or len(chunk) > len(merged[tid]):
            merged[tid] = chunk

    ordered = [merged[t] for t in sorted(merged)]
    with open(ours_path, "w") as f:
        f.write(header_o.rstrip() + "\n\n" + "\n".join(ordered).rstrip() + "\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
