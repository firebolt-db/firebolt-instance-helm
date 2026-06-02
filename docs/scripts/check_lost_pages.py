#!/usr/bin/env python3
"""Ensure every published MDX file is listed in docs.json navigation."""

from __future__ import annotations

import json
import pathlib
import pprint
import re
import sys
from collections.abc import Iterator
from typing import Any


class LostPagesError(Exception):
    pass


def group_collect_pages(pages: list[Any]) -> Iterator[str]:
    if not isinstance(pages, list):
        raise LostPagesError(f"Expected a list of pages, got {type(pages)}: {pprint.pformat(pages)}")
    if not pages:
        raise LostPagesError("Expected at least one page in the group")
    for page in pages:
        if isinstance(page, str):
            yield page
        elif isinstance(page, dict):
            if "groups" in page:
                yield from group_collect_pages(page["groups"])
            elif "pages" in page:
                yield from group_collect_pages(page["pages"])
            elif "href" in page or "openapi" in page:
                continue
            else:
                raise LostPagesError(f"Unexpected entry: {page}")
        else:
            raise LostPagesError(f"Unexpected entry: {page}")


def check_lost_pages(docs_dir: pathlib.Path, navigation_groups: list[Any]) -> None:
    navigatable_pages = {f"{page}.mdx" for page in group_collect_pages(navigation_groups)}

    lost_pages: set[str] = set()
    for path in docs_dir.glob("**/*.mdx"):
        rel_path = path.relative_to(docs_dir)
        if rel_path.parts[0] == "slides":
            continue
        rel_str = str(rel_path)
        if rel_str not in navigatable_pages:
            lost_pages.add(rel_str)

    lost_pages.discard("index.mdx")
    if lost_pages:
        raise LostPagesError(
            "Found MDX files that are not listed in docs.json navigation:\n"
            + "\n".join(f"  - {page}" for page in sorted(lost_pages))
            + "\n\nAdd them to docs.json navigation."
        )


def main() -> int:
    docs_dir = pathlib.Path(__file__).resolve().parent.parent
    docs_json = json.loads((docs_dir / "docs.json").read_text(encoding="utf-8"))
    groups = docs_json.get("navigation", {}).get("groups")
    if not isinstance(groups, list):
        print("Expected navigation.groups in docs.json", file=sys.stderr)
        return 1
    try:
        check_lost_pages(docs_dir, groups)
    except LostPagesError as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
