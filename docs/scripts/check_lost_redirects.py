#!/usr/bin/env python3
"""Flag removed/renamed docs pages that lack a redirect.

These docs are aggregated into the packdb Mintlify site, where packdb keeps a
``known_pages.json`` gate that refuses to drop a previously published URL
without a redirect. Redirects for *these* pages must be authored here -- in
this repo's ``docs.json`` ``redirects`` array, in the same slug namespace as
the pages (leading slash, no ``self-managed/...`` prefix). The packdb
aggregation prefixes and propagates them into the global site automatically.

This guard mirrors packdb's check so the requirement surfaces at authoring
time, in the PR that removes the page, rather than as a downstream CI failure.

Usage:
  check_lost_redirects.py            # verify (fails on a stale known_pages.json)
  check_lost_redirects.py regenerate # rewrite known_pages.json after a change

Stdlib-only by design (no venv needed in CI).
"""

from __future__ import annotations

import json
import pathlib
import re
import sys


class LostRedirectsError(Exception):
    pass


def check_lost_redirects(
    docs_dir: pathlib.Path,
    docs_json: dict,
    known_pages_path: pathlib.Path,
    regenerate: bool,
) -> None:
    known_pages = set(json.loads(known_pages_path.read_text())) if known_pages_path.exists() else set()

    slugs = set()
    redirect_pages = set()
    for r in docs_json.get("redirects", []):
        if re.match("^.*?/:\\w+[*]", r["source"]):
            src = re.sub("^(.*/):\\w+[*]", r"\1(.*)", r["source"])
            slugs.add(src)
        else:
            # A single authored redirect covers both the bare slug and its
            # trailing-slash variant (packdb's gate tracks both); aggregation
            # emits both source forms downstream.
            redirect_pages.add(r["source"])
            if r["source"].startswith("/") and not r["source"].endswith("/"):
                redirect_pages.add(f'{r["source"]}/')

    existing_pages = set()
    for page_path in sorted(docs_dir.glob("**/*.mdx")):
        rel_page_path = page_path.relative_to(docs_dir)
        if str(rel_page_path).startswith("snippets/"):
            continue
        page = f'/{str(rel_page_path).removesuffix(".mdx").removeprefix("./")}'
        existing_pages.add(page)
        redirect_pages.add(f"{page}/")
        if page_path.parent != docs_dir and not page_path.parent.with_suffix(".mdx").exists():
            # If the overview page doesn't exist, Mintlify auto-redirects to one
            # of the group's pages; treat the overview slug as still reachable.
            redirect_pages.add(str(pathlib.Path(page).parent))
            redirect_pages.add(f"{str(pathlib.Path(page).parent)}/")

    for page in sorted(known_pages):
        if page not in existing_pages and page not in redirect_pages and not any(re.match(src, page) for src in slugs):
            raise LostRedirectsError(
                f"Page {page} was previously published but no longer exists and has no redirect. "
                f"Add a redirect for it to docs.json (e.g. "
                f'{{"source": "{page}", "destination": "/<new-page>", "permanent": false}}), '
                f"then run 'make -C docs check-lost-redirects-regenerate'. "
                f"packdb aggregation prefixes and propagates this redirect into the published site."
            )

    new_known_pages = known_pages | existing_pages | redirect_pages
    if new_known_pages != known_pages:
        if regenerate:
            known_pages_path.write_text(json.dumps(sorted(new_known_pages), indent=2) + "\n")
        else:
            raise LostRedirectsError(
                "The known pages list is out of date. "
                "Run 'make -C docs check-lost-redirects-regenerate' to update it."
            )


def main(root_dir: pathlib.Path, regenerate: bool) -> int:
    docs_json = json.loads((root_dir / "docs.json").read_text())
    known_pages_path = root_dir / "known_pages.json"
    try:
        check_lost_redirects(root_dir, docs_json, known_pages_path, regenerate)
    except LostRedirectsError as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(
        main(
            pathlib.Path(__file__).resolve().parent.parent,
            len(sys.argv) > 1 and sys.argv[1] == "regenerate",
        )
    )
