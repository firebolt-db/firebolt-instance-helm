#!/usr/bin/env python3
"""Validate Helm chart docs.json against packdb Self-Managed nesting rules after aggregation."""

from __future__ import annotations

import json
import pathlib
import sys
from typing import Any

from check_group_structure import GroupStructureError, check_group_structure

# Must match packdb docs/multirepo-aggregate-repos.yaml target for this repo.
AGGREGATE_PREFIX = "self-managed/helm-chart"

# Representative native Self-Managed entry so the Helm Chart group is checked in
# the same mixed navigation context as production.
_SAMPLE_SELF_MANAGED_GROUP: dict[str, Any] = {
    "group": "Self-Managed",
    "pages": [
        {
            "group": "Example Self-Managed Product",
            "pages": [
                "self-managed/example-product",
                "self-managed/example-product/installation",
            ],
        }
    ],
}


def _prepend_prefix(entry: Any, prefix: str) -> Any:
    if isinstance(entry, str):
        return f"{prefix}/{entry}"
    if isinstance(entry, dict) and "pages" in entry:
        return {**entry, "pages": [_prepend_prefix(page, prefix) for page in entry["pages"]]}
    if isinstance(entry, dict) and ("href" in entry or "openapi" in entry):
        return entry
    raise GroupStructureError(f"Unsupported navigation entry: {entry!r}")


def _helm_group_from_docs_json(docs_json: dict[str, Any]) -> dict[str, Any]:
    groups = docs_json.get("navigation", {}).get("groups")
    if not isinstance(groups, list) or len(groups) != 1:
        raise GroupStructureError("Expected docs.json navigation.groups to contain exactly one group")
    group = groups[0]
    if not isinstance(group, dict) or "group" not in group or "pages" not in group:
        raise GroupStructureError(f"Expected a navigation group with 'group' and 'pages', got {group!r}")
    return group


def build_aggregated_docs_tabs(helm_group: dict[str, Any]) -> list[dict[str, Any]]:
    prefixed_helm = {
        **helm_group,
        "pages": [_prepend_prefix(page, AGGREGATE_PREFIX) for page in helm_group["pages"]],
    }
    self_managed_group = {
        **_SAMPLE_SELF_MANAGED_GROUP,
        "pages": [*_SAMPLE_SELF_MANAGED_GROUP["pages"], prefixed_helm],
    }
    return [
        {
            "tab": "Documentation",
            "groups": [
                self_managed_group,
            ],
        },
    ]


def check_helm_navigation(docs_json: dict[str, Any]) -> None:
    helm_group = _helm_group_from_docs_json(docs_json)
    tabs = build_aggregated_docs_tabs(helm_group)
    check_group_structure(tabs, -1)


def main() -> int:
    docs_dir = pathlib.Path(__file__).resolve().parent.parent
    docs_json_path = docs_dir / "docs.json"
    docs_json = json.loads(docs_json_path.read_text(encoding="utf-8"))
    try:
        check_helm_navigation(docs_json)
    except GroupStructureError as exc:
        print(f"Navigation structure error: {exc}", file=sys.stderr)
        print(
            f"\nPaths are checked as they appear after packdb aggregation "
            f"(prefix '{AGGREGATE_PREFIX}/') under Documentation → Self-Managed → Helm Chart.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
