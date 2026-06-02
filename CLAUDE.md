# CLAUDE.md

## Agent Configuration
This repository follows the **AGENTS.md** specification (https://agents.md/).
- **Hierarchy:** Always check for an `AGENTS.md` file in the root directory for project-wide context.
- **Scoped Instructions:** `AGENTS.md` files may also live in **subfolders**. Those provide more granular, module-scoped instructions. Always prioritize the most local `AGENTS.md` relative to the files you are editing, falling back to the root for project-wide rules.

## Workflow
- Before performing a task, read the relevant `AGENTS.md` files (most-local first, then root).
