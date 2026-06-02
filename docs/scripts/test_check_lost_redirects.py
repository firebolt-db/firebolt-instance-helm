#!/usr/bin/env python3

from __future__ import annotations

import json
import pathlib
import tempfile
import unittest

from check_lost_redirects import LostRedirectsError, check_lost_redirects


def _write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class CheckLostRedirectsTest(unittest.TestCase):
    def _docs_dir(self, stack: tempfile.TemporaryDirectory) -> pathlib.Path:
        return pathlib.Path(stack.name)

    def test_new_page_is_accepted_and_regenerated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            docs_dir = pathlib.Path(tmp)
            _write(docs_dir / "installation.mdx", "x")
            known = docs_dir / "known_pages.json"
            known.write_text(json.dumps([]))

            check_lost_redirects(docs_dir, {}, known, regenerate=True)

            self.assertIn("/installation", json.loads(known.read_text()))

    def test_removed_page_without_redirect_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            docs_dir = pathlib.Path(tmp)
            # No mdx files exist, but the page was previously known.
            known = docs_dir / "known_pages.json"
            known.write_text(json.dumps(["/architecture/old-name"]))

            with self.assertRaises(LostRedirectsError) as ctx:
                check_lost_redirects(docs_dir, {}, known, regenerate=True)
            self.assertIn("/architecture/old-name", str(ctx.exception))

    def test_removed_page_with_redirect_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            docs_dir = pathlib.Path(tmp)
            _write(docs_dir / "architecture" / "new-name.mdx", "x")
            known = docs_dir / "known_pages.json"
            known.write_text(json.dumps(["/architecture/old-name"]))
            docs_json = {
                "redirects": [
                    {"source": "/architecture/old-name", "destination": "/architecture/new-name"}
                ]
            }

            check_lost_redirects(docs_dir, docs_json, known, regenerate=True)

            known_pages = json.loads(known.read_text())
            self.assertIn("/architecture/new-name", known_pages)

    def test_single_redirect_covers_trailing_slash_variant(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            docs_dir = pathlib.Path(tmp)
            _write(docs_dir / "architecture" / "new-name.mdx", "x")
            known = docs_dir / "known_pages.json"
            # Both the bare and trailing-slash variants of the removed page were
            # previously known.
            known.write_text(
                json.dumps(["/architecture/old-name", "/architecture/old-name/"])
            )
            docs_json = {
                "redirects": [
                    {"source": "/architecture/old-name", "destination": "/architecture/new-name"}
                ]
            }

            # A missing redirect for either variant would raise the
            # "previously published" error before the staleness check, so this
            # completing proves one authored redirect covers both variants.
            check_lost_redirects(docs_dir, docs_json, known, regenerate=True)

    def test_stale_list_fails_without_regenerate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            docs_dir = pathlib.Path(tmp)
            _write(docs_dir / "installation.mdx", "x")
            known = docs_dir / "known_pages.json"
            known.write_text(json.dumps([]))

            with self.assertRaises(LostRedirectsError):
                check_lost_redirects(docs_dir, {}, known, regenerate=False)


if __name__ == "__main__":
    unittest.main()
