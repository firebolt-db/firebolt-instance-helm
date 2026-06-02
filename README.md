# firebolt-instance-helm

[![CI](https://img.shields.io/github/checks-status/firebolt-db/firebolt-instance-helm/main?label=CI)](https://github.com/firebolt-db/firebolt-instance-helm/actions?query=branch%3Amain)
[![Chart Version](https://img.shields.io/github/v/tag/firebolt-db/firebolt-instance-helm?label=chart&sort=semver)](https://github.com/firebolt-db/firebolt-instance-helm/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

Helm chart for running a Firebolt instance on Kubernetes: Envoy gateway, Metadata Service, PostgreSQL, and one or more Firebolt query engine StatefulSets.

The chart is published as `firebolt-instance` to `oci://ghcr.io/firebolt-db/helm-charts` on every change to `helm/` merged to `main`.

## Scope

The chart deploys a complete Firebolt instance — gateway, metadata, PostgreSQL, engines — into any Kubernetes cluster. For day-2 operational capabilities (zero-downtime engine rollouts, autoscaling, drift correction, reusable per-engine templates), use the [Firebolt Kubernetes Operator](docs/operator-upgrade-path.mdx). See [`docs/`](docs/) for usage patterns.

## Architecture

```
        client ── HTTP ──▶ Envoy gateway ──┐
                                            │  routes by X-Firebolt-Engine
                                            ▼
                                  ┌──────── engines ────────┐
                                  │ default StatefulSet(s)  │
                                  │ analytics StatefulSet(s)│
                                  │ ...                     │
                                  └────────────┬────────────┘
                                               │
                              metadata service ◀── PostgreSQL
```

Each entry under `engines:` becomes one 1-replica StatefulSet per node plus a shared headless Service, ClusterIP Service, and ConfigMap.

## Quick start

Engines require object storage to start — see [`docs/usage/managed-storage.mdx`](docs/usage/managed-storage.mdx). With a values file that configures it:

```sh
make create                                # kind create cluster
helm install firebolt ./helm \
  --namespace firebolt --create-namespace \
  -f my-values.yaml                        # must set customEngineConfig.storage
make test                                  # run `helm test` (engine ready, gateway ready, smoke SQL, ...)
make cleanup                               # uninstall release, delete PVCs, delete namespace
make delete                                # kind delete cluster
```

See [`docs/usage/single-engine.mdx`](docs/usage/single-engine.mdx) for the full walkthrough, [`docs/prerequisites.mdx`](docs/prerequisites.mdx) for cluster requirements, and [`docs/`](docs/) for additional patterns (multi-engine, external PostgreSQL, image overrides).

## How it works

The Envoy gateway extracts the `X-Firebolt-Engine` header via a Lua filter and rewrites the upstream to the matching engine Service. The metadata service serves table-and-engine metadata to engines over gRPC, scoped to the `customEngineConfig.instance.id` ULID. PostgreSQL is bundled by default for development; production deployments should set `postgresql.local_enabled: false` and provide an external database.

## Where to go next

- **User-facing docs** are under [`docs/`](docs/), authored as Mintlify MDX with navigation in [`docs/docs.json`](docs/docs.json): [overview](docs/overview.mdx), [prerequisites](docs/prerequisites.mdx), usage patterns ([single engine](docs/usage/single-engine.mdx), [multi-engine](docs/usage/multi-engine.mdx), [managed storage](docs/usage/managed-storage.mdx), [external PostgreSQL](docs/usage/external-postgres.mdx), [image overrides](docs/usage/image-overrides.mdx)), the [operator upgrade path](docs/operator-upgrade-path.mdx), and [troubleshooting](docs/troubleshooting.mdx).
- The full **configuration reference** is generated from `helm/values.yaml` and lives at [`helm/README.md`](./helm/README.md).
- For **contributor** detail, conventions, and rules for making changes to this repo, see [`AGENTS.md`](AGENTS.md). Module-specific rules for the chart itself live in [`helm/AGENTS.md`](helm/AGENTS.md).
- Changelog: [`helm/CHANGELOG.md`](./helm/CHANGELOG.md).
- Security policy: [`SECURITY.md`](./SECURITY.md).
