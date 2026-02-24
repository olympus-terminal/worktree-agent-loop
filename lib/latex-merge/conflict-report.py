#!/usr/bin/env python3
"""conflict-report.py — Human-readable conflict summary for .tex files.

Parses git conflict markers in a file and reports per-section conflicts
with context for easier resolution.

Usage:
    python3 conflict-report.py <conflicted_file.tex>
"""

import re
import sys
from pathlib import Path
from dataclasses import dataclass

CONFLICT_START = re.compile(r'^<<<<<<<\s*(.*)')
CONFLICT_MID   = re.compile(r'^=======')
CONFLICT_END   = re.compile(r'^>>>>>>>\s*(.*)')
SECTION_RE     = re.compile(r'\\(?:section|subsection|subsubsection)\*?\{(.+?)\}')

@dataclass
class Conflict:
    """A single conflict region."""
    start_line: int
    end_line: int
    ours_label: str
    theirs_label: str
    ours_lines: list
    theirs_lines: list
    section: str  # Nearest section heading

def find_nearest_section(lines: list, line_num: int) -> str:
    """Walk backwards to find the nearest \\section heading."""
    for i in range(line_num, -1, -1):
        m = SECTION_RE.search(lines[i])
        if m:
            return m.group(1)
    return "(preamble)"

def parse_conflicts(filepath: Path) -> list:
    """Parse conflict markers from a file."""
    lines = filepath.read_text(encoding='utf-8').splitlines()
    conflicts = []
    i = 0

    while i < len(lines):
        m = CONFLICT_START.match(lines[i])
        if m:
            ours_label = m.group(1).strip()
            start_line = i + 1  # 1-indexed
            ours_lines = []
            theirs_lines = []
            in_theirs = False
            theirs_label = ""
            i += 1

            while i < len(lines):
                if CONFLICT_MID.match(lines[i]):
                    in_theirs = True
                    i += 1
                    continue

                m_end = CONFLICT_END.match(lines[i])
                if m_end:
                    theirs_label = m_end.group(1).strip()
                    break

                if in_theirs:
                    theirs_lines.append(lines[i])
                else:
                    ours_lines.append(lines[i])
                i += 1

            section = find_nearest_section(lines, start_line - 1)
            conflicts.append(Conflict(
                start_line=start_line,
                end_line=i + 1,
                ours_label=ours_label,
                theirs_label=theirs_label,
                ours_lines=ours_lines,
                theirs_lines=theirs_lines,
                section=section,
            ))
        i += 1

    return conflicts

def format_report(filepath: Path, conflicts: list) -> str:
    """Format a human-readable conflict report."""
    lines = []
    lines.append(f"Conflict Report: {filepath.name}")
    lines.append("=" * 60)
    lines.append(f"Total conflicts: {len(conflicts)}")
    lines.append("")

    # Group by section
    sections = {}
    for c in conflicts:
        sections.setdefault(c.section, []).append(c)

    for section, section_conflicts in sections.items():
        lines.append(f"Section: {section}")
        lines.append("-" * 40)

        for idx, c in enumerate(section_conflicts, 1):
            lines.append(f"  Conflict {idx} (lines {c.start_line}-{c.end_line}):")
            lines.append(f"    Ours ({c.ours_label}): {len(c.ours_lines)} line(s)")
            lines.append(f"    Theirs ({c.theirs_label}): {len(c.theirs_lines)} line(s)")

            # Show preview (first 3 lines of each side)
            if c.ours_lines:
                lines.append("    Ours preview:")
                for ol in c.ours_lines[:3]:
                    lines.append(f"      | {ol}")
                if len(c.ours_lines) > 3:
                    lines.append(f"      ... (+{len(c.ours_lines) - 3} more)")

            if c.theirs_lines:
                lines.append("    Theirs preview:")
                for tl in c.theirs_lines[:3]:
                    lines.append(f"      | {tl}")
                if len(c.theirs_lines) > 3:
                    lines.append(f"      ... (+{len(c.theirs_lines) - 3} more)")

            lines.append("")

    return '\n'.join(lines)

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <conflicted_file.tex>", file=sys.stderr)
        sys.exit(1)

    filepath = Path(sys.argv[1])
    if not filepath.exists():
        print(f"Error: {filepath} not found", file=sys.stderr)
        sys.exit(1)

    conflicts = parse_conflicts(filepath)

    if not conflicts:
        print(f"No conflict markers found in {filepath.name}")
        return

    report = format_report(filepath, conflicts)
    print(report)

if __name__ == '__main__':
    main()
