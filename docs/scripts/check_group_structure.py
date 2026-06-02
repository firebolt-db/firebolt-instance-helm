#!/usr/bin/env python3
"""Navigation path-depth checker (synced from packdb/docs/scripts/check_group_structure.py)."""

import json
import pathlib
import pprint
import string


class GroupStructureError(Exception):
    pass


def check_group_structure(pages: list[str | dict], level: int) -> list[str]:
    if not isinstance(pages, list):
        raise GroupStructureError(f"Expected a list of pages, got {type(pages)}: {pprint.pformat(pages)}")
    if not pages:
        raise GroupStructureError("Expected at least one page in the group")
    common_path = None
    for p in pages:
        if isinstance(p, str):
            if p.startswith("/") or p.endswith("/") or set(p).difference(set("/-_" + string.ascii_lowercase + string.digits)):
                raise GroupStructureError(f"Page address is not allowed: {p}")
            p_parts = p.split("/")
            if len(p_parts) == level:
                if common_path is None:
                    common_path = p_parts
                elif p_parts != common_path:
                    raise GroupStructureError(
                        f"At most one page is allowed at level {level} directory depth, found {common_path} and {p}"
                    )
            elif len(p_parts) != level + 1:
                raise GroupStructureError(f"Expected all pages to be at {level + 1} directory depth, found {p}")
            elif common_path is None:
                common_path = p_parts[:level]
            elif p_parts[:level] != common_path:
                raise GroupStructureError(
                    f"Expected all pages in the group to have the same path prefix, got {p} with prefix {p_parts[:level]} instead of {common_path}"
                )
        elif isinstance(p, dict):
            if "groups" in p:
                sub_common_path = check_group_structure(p["groups"], level + 1)
                if len(sub_common_path) != level + 1:
                    raise GroupStructureError(f"Unexpected common path {sub_common_path} at depth {level + 1}")
                if common_path is None:
                    common_path = sub_common_path[:level]
                elif sub_common_path[:level] != common_path:
                    raise GroupStructureError(
                        f"Expected all pages in the group to have the same path prefix, got {p} with prefix {sub_common_path} instead of {common_path}"
                    )
            elif "pages" in p:
                sub_common_path = check_group_structure(p["pages"], level + 1)
                if len(sub_common_path) != level + 1:
                    raise GroupStructureError(f"Unexpected common path {sub_common_path} at depth {level + 1}")
                if common_path is None:
                    common_path = sub_common_path[:level]
                elif sub_common_path[:level] != common_path:
                    raise GroupStructureError(
                        f"Expected all pages in the group to have the same path prefix, got {p} with prefix {sub_common_path} instead of {common_path}"
                    )
            elif "href" in p or "openapi" in p:
                continue
            else:
                raise GroupStructureError(f"Unexpected entry: {p}")
        else:
            raise GroupStructureError(f"Unexpected entry: {p}")
    if common_path is None:
        raise GroupStructureError("Expected at least one page in the group")
    return common_path
