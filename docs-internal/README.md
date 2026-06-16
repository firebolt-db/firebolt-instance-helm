# Internal documentation

Firebolt-internal notes for working with this repo. Not for external consumption — anything that should be public belongs in [`../docs/`](../docs/).

## Contents

- [Local development](local-development.md) — the `make dev` flow (engine/metadata at the mutable `:dev` tag), with floci as the managed-storage S3 emulator.
- [Agentic local deployment](agentic-deployment.md) — `make agent-up` / `make agent-down`: a single-command, machine-parseable path for AI agents to deploy to kind, smoke-test, and tear down.
