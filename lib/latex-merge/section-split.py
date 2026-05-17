#!/usr/bin/env python3
"""section-split.py — Split a .tex file at \\section boundaries.

Writes numbered section files + MANIFEST.txt for reassembly.

Usage:
    python3 section-split.py <input.tex> [output_dir]

Output:
    output_dir/
    ├── MANIFEST.txt       # Ordered list of section files
    ├── 000_preamble.tex   # Everything before first \\section
    ├── 001_introduction.tex
    ├── 002_methods.tex
    └── ...
"""

import re
import sys
import os
from pathlib import Path

# Match \section{...}, \section*{...}, \subsection{...}, etc.
SECTION_RE = re.compile(
    r'^(\\(?:section|subsection|subsubsection)\*?\{.*?\})',
    re.MULTILINE
)

def slugify(title: str) -> str:
    """Convert section title to filesystem-safe slug."""
    # Extract text from \section{Title Here}
    m = re.search(r'\{(.+?)\}', title)
    text = m.group(1) if m else title
    # Lowercase, replace non-alnum with underscore
    slug = re.sub(r'[^a-z0-9]+', '_', text.lower()).strip('_')
    return slug[:50]  # Truncate long titles

def split_sections(content: str):
    """Split LaTeX content into (header, body) pairs.

    Returns list of (section_header_or_'preamble', body_text) tuples.
    """
    sections = []
    parts = SECTION_RE.split(content)

    # parts[0] is preamble (before first section)
    if parts[0].strip():
        sections.append(('preamble', parts[0]))

    # Remaining parts alternate: header, body, header, body, ...
    i = 1
    while i < len(parts):
        header = parts[i]
        body = parts[i + 1] if i + 1 < len(parts) else ''
        sections.append((header, header + body))
        i += 2

    return sections

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.tex> [output_dir]", file=sys.stderr)
        sys.exit(1)

    input_file = Path(sys.argv[1])
    if not input_file.exists():
        print(f"Error: {input_file} not found", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else input_file.parent / f"{input_file.stem}_sections"
    output_dir.mkdir(parents=True, exist_ok=True)

    content = input_file.read_text(encoding='utf-8')
    sections = split_sections(content)

    manifest = []
    for idx, (header, body) in enumerate(sections):
        slug = slugify(header)
        filename = f"{idx:03d}_{slug}.tex"
        filepath = output_dir / filename
        filepath.write_text(body, encoding='utf-8')
        manifest.append(filename)
        print(f"  {filename} ({len(body.splitlines())} lines)")

    # Write manifest
    manifest_path = output_dir / "MANIFEST.txt"
    manifest_path.write_text('\n'.join(manifest) + '\n', encoding='utf-8')

    print(f"\nSplit into {len(sections)} section(s) in {output_dir}/")
    print(f"Manifest: {manifest_path}")

if __name__ == '__main__':
    main()
