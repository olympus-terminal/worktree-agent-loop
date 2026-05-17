#!/usr/bin/env python3
"""section-merge.py — Reassemble a .tex file from split sections.

Reads MANIFEST.txt and concatenates section files in order.

Usage:
    python3 section-merge.py <sections_dir> [output.tex]
"""

import sys
from pathlib import Path

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <sections_dir> [output.tex]", file=sys.stderr)
        sys.exit(1)

    sections_dir = Path(sys.argv[1])
    manifest_path = sections_dir / "MANIFEST.txt"

    if not manifest_path.exists():
        print(f"Error: MANIFEST.txt not found in {sections_dir}", file=sys.stderr)
        sys.exit(1)

    filenames = [
        line.strip()
        for line in manifest_path.read_text(encoding='utf-8').splitlines()
        if line.strip()
    ]

    parts = []
    for filename in filenames:
        filepath = sections_dir / filename
        if not filepath.exists():
            print(f"Warning: {filename} not found, skipping", file=sys.stderr)
            continue
        parts.append(filepath.read_text(encoding='utf-8'))

    merged = ''.join(parts)

    if len(sys.argv) > 2:
        output_path = Path(sys.argv[2])
        output_path.write_text(merged, encoding='utf-8')
        print(f"Merged {len(filenames)} section(s) -> {output_path}")
    else:
        sys.stdout.write(merged)

if __name__ == '__main__':
    main()
