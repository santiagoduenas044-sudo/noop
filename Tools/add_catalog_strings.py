#!/usr/bin/env python3
"""Add keys (with translations) to an Apple String Catalog, idempotently.

Preserves the catalog's exact on-disk formatting (json.dumps with indent=2,
ensure_ascii=False, insertion order + trailing newline round-trips byte-identically),
so adding a handful of strings produces a small, reviewable diff instead of
rewriting all 3000+ entries. New keys are appended in insertion order; the catalog
is not globally sorted (Xcode's own ordering is not strictly alphabetical).

Usage: add_catalog_strings.py <catalog.xcstrings> <entries.json>
  entries.json: {"English source text": {"de": "...", "es": "...", "fr": "..."}}
"""
import json
import sys
from pathlib import Path


def add(catalog_path: str, entries: dict) -> int:
    p = Path(catalog_path)
    cat = json.loads(p.read_text())
    strings = cat["strings"]
    added = 0
    for key, translations in entries.items():
        node = strings.setdefault(key, {})
        locs = node.setdefault("localizations", {})
        for lang, value in translations.items():
            if lang in locs:
                continue  # never clobber an existing (possibly hand-corrected) translation
            locs[lang] = {"stringUnit": {"state": "translated", "value": value}}
            added += 1
    p.write_text(json.dumps(cat, indent=2, ensure_ascii=False) + "\n")
    return added


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    entries = json.loads(Path(sys.argv[2]).read_text())
    print(f"added {add(sys.argv[1], entries)} localization(s)")
