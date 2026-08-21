#!/usr/bin/env python3
"""workspaceOpen loader: print pluginPaths for cursor-ralph-profile. Fail open."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def _profile_root() -> Path | None:
    env = os.environ.get("CURSOR_RALPH_PROFILE_ROOT", "").strip()
    if env:
        candidate = Path(env)
        if _is_profile(candidate):
            return candidate.resolve()
    local = Path(".cursor/ralph-profile.local.json")
    if local.is_file():
        try:
            data = json.loads(local.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        raw = str(data.get("profileRoot") or "").strip()
        if raw:
            candidate = Path(raw)
            if _is_profile(candidate):
                return candidate.resolve()
    return None


def _is_profile(path: Path) -> bool:
    manifest = path / ".cursor-plugin" / "plugin.json"
    if not manifest.is_file():
        return False
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return data.get("name") == "cursor-ralph-profile"


def main() -> int:
    try:
        sys.stdin.read()
    except OSError:
        pass
    root = _profile_root()
    if root is None:
        sys.stdout.write("{}\n")
        return 0
    sys.stdout.write(json.dumps({"pluginPaths": [str(root)]}) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
