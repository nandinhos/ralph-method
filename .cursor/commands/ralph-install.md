---
name: ralph-install
description: Activate cursor-ralph-profile in the current project. Open the target repo, run this command, reload the window. Does not install Ralph Method and does not commit.
---

# ralph-install

You are installing the **cursor-ralph-profile** plugin into the **current workspace** (the product repo). After a reload, `/ralph-init`, `/ralph-plan` and `/ralph-ai-context` load only in that project.

This is not Ralph Method `ralph-init apply`. This is not a git commit. Do not read `.env`. Do not copy the plugin tree into the project (that would fork the runner).

## Objective

1. Resolve the profile checkout (folder that contains `.cursor-plugin/plugin.json` with `"name": "cursor-ralph-profile"`).
2. Run the installer against the **target project root**.
3. Tell the developer to reload Cursor and reopen the project.

## Resolve paths

**Profile root** (first hit):

1. `CURSOR_RALPH_PROFILE_ROOT` if set and valid
2. HTML comment `cursor-ralph-profile-root:` in this file, if present
3. Parent of `commands/ralph-install.md` when this file lives inside the profile checkout
4. `%USERPROFILE%\Projects\cursor-ralph-profile` or `~/Projects/cursor-ralph-profile` (also `projects` lowercase)

**Project root**:

- Default: current workspace root
- If the user passed a path, use that path
- If the current workspace **is** the profile checkout and no path was given: run the installer with `--user-command-only` only, then stop. Ask which product repo to activate.

Refuse if the target does not exist. Refuse to dump the whole plugin into the target.

## Run

Windows (PowerShell):

```powershell
python "<PROFILE>\scripts\install-into-project.py" --profile-root "<PROFILE>" --project-root "<PROJECT>"
```

Git Bash / macOS / Linux:

```bash
python3 "<PROFILE>/scripts/install-into-project.py" --profile-root "<PROFILE>" --project-root "<PROJECT>"
```

If Python is missing, use the wrapper in the same folder (`install-into-project.ps1` or `install-into-project.sh`).

The installer is idempotent. It must:

- write `~/.cursor/commands/ralph-install.md` (so `/ralph-install` exists in any project)
- write `.cursor/ralph-profile.local.json` (machine path; gitignored under `.cursor/`)
- copy `.cursor/hooks/ralph-load-profile.py` and `.cmd`
- merge `workspaceOpen` into `.cursor/hooks.json` (fail open, do not wipe other hooks)
- copy this command to `.cursor/commands/ralph-install.md` in the project

## Report

Quote the installer stdout. Then tell the developer, in this order:

1. Command palette → **Developer: Reload Window** (or close and reopen Cursor)
2. Reopen **this** project
3. Confirm `/ralph-init` appears in the slash list
4. Next hop is `/ralph-init` — not implementation, not `ralph.sh`

If reload is required, stop. Do not start `/ralph-init` in the same turn.

## Rules

- No git writes.
- No `ralph-init apply` and no `ralph.sh` unless the developer asked in the same message.
- No `CURSOR_API_KEY` in any written file.
- Other projects stay untouched except the user-level `/ralph-install` bootstrap.
