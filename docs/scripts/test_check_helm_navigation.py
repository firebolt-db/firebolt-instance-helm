#!/usr/bin/env python3

from __future__ import annotations

import unittest

from check_helm_navigation import AGGREGATE_PREFIX, build_aggregated_docs_tabs, check_helm_navigation


class HelmNavigationTest(unittest.TestCase):
    def test_check_helm_navigation_allows_href_and_openapi_entries(self) -> None:
        docs_json = {
            "navigation": {
                "groups": [
                    {
                        "group": "Helm Chart",
                        "pages": [
                            "overview",
                            {"href": "https://example.com", "label": "External docs"},
                            {"openapi": "openapi.json"},
                            "prerequisites",
                        ],
                    }
                ]
            }
        }

        check_helm_navigation(docs_json)

    def test_build_aggregated_docs_tabs_leaves_href_and_openapi_entries_unprefixed(self) -> None:
        href_entry = {"href": "https://example.com", "label": "External docs"}
        openapi_entry = {"openapi": "openapi.json"}
        helm_group = {
            "group": "Helm Chart",
            "pages": [
                "overview",
                href_entry,
                openapi_entry,
            ],
        }

        tabs = build_aggregated_docs_tabs(helm_group)
        helm_pages = tabs[0]["groups"][0]["pages"][1]["pages"]

        self.assertEqual(f"{AGGREGATE_PREFIX}/overview", helm_pages[0])
        self.assertIs(href_entry, helm_pages[1])
        self.assertIs(openapi_entry, helm_pages[2])


if __name__ == "__main__":
    unittest.main()
