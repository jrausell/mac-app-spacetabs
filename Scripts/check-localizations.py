#!/usr/bin/env python3
"""Validate translation coverage and numbered arguments without third-party packages."""

from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = ROOT / "Sources/SpaceTabsCore/Localization/Resources"
# Catalog entries use JSON-compatible quoted strings, one entry per line. This
# subset is also accepted by Apple's .strings reader and keeps diffs readable.
ENTRY = re.compile(r'^("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");$')
PLACEHOLDER = re.compile(r"\{\d+\}")


def read_catalog(path: Path) -> dict[str, str]:
    entries = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.strip().startswith("/*"):
            continue
        match = ENTRY.fullmatch(line)
        if not match:
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: invalid catalog entry")
        key, value = map(json.loads, match.groups())
        if key in entries:
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: duplicate key: {key}")
        if not value:
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: empty translation: {key}")
        if Counter(PLACEHOLDER.findall(key)) != Counter(PLACEHOLDER.findall(value)):
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: changed placeholders: {key}")
        entries[key] = value
    return entries


def main() -> int:
    try:
        catalogs = {path.parent.stem: read_catalog(path) for path in sorted(DIRECTORY.glob("*.lproj/Localizable.strings"))}
        english = catalogs["en"]
        source = (ROOT / "Sources/SpaceTabsCore/Localization/AppLanguage.swift").read_text(encoding="utf-8")
        supported = set(re.findall(r'case\s+\w+\s*=\s*"([a-zA-Z-]+)"', source))
        if set(catalogs) != supported:
            raise ValueError("AppLanguage cases and .lproj catalogs must list the same supported languages")
        if not english or any(key != value for key, value in english.items()):
            raise ValueError("English values must match their source keys")
        for language, entries in catalogs.items():
            if set(entries) != set(english):
                missing = sorted(set(english) - set(entries))
                extra = sorted(set(entries) - set(english))
                raise ValueError(f"{language}: missing keys: {missing}; extra keys: {extra}")
        print(f"Checked {len(english)} entries in {len(catalogs)} language catalogs.")
        return 0
    except (ValueError, KeyError, OSError) as error:
        print(f"Localization check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
