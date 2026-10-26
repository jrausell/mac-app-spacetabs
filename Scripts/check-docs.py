#!/usr/bin/env python3
"""Check local Markdown links without fetching external sites."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
DOCUMENTS = sorted(ROOT.glob("*.md")) + sorted((ROOT / "docs").rglob("*.md")) + sorted((ROOT / ".github").rglob("*.md"))
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FENCE = re.compile(r"```.*?```", re.DOTALL)


def main() -> int:
    errors = []
    for document in DOCUMENTS:
        text = FENCE.sub("", document.read_text(encoding="utf-8"))
        for match in LINK.finditer(text):
            target = match.group(1).strip().strip("<>")
            parts = urlsplit(target)
            if parts.scheme or parts.netloc or not parts.path:
                continue
            path = (document.parent / unquote(parts.path)).resolve()
            if not path.exists():
                errors.append(f"{document.relative_to(ROOT)}: missing link target: {target}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Checked local links in {len(DOCUMENTS)} Markdown files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
