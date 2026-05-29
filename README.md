# firebolt-instance-helm

[![CI](https://img.shields.io/github/checks-status/firebolt-db/firebolt-instance-helm/main?label=CI)](https://github.com/firebolt-db/firebolt-instance-helm/actions?query=branch%3Amain)
[![Chart Version](https://img.shields.io/github/v/tag/firebolt-db/firebolt-instance-helm?label=chart&sort=semver)](https://github.com/firebolt-db/firebolt-instance-helm/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

Helm chart for running a Firebolt instance on Kubernetes: Envoy gateway, Pensieve metadata service, PostgreSQL, and one or more `firebolt-core` query engine StatefulSets.

The chart is published as `firebolt-instance` to `oci://ghcr.io/firebolt-db/helm-charts` on every change to `helm/` merged to `main`.

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
                              metadata (Pensieve) ◀── PostgreSQL
```

Each entry under `engines:` becomes one 1-replica StatefulSet per node plus a shared headless Service, ClusterIP Service, and ConfigMap.

## Quick start

```sh
make create     # kind create cluster
make dev        # deploy floci + refresh ECR pull secret + helm install with helm/values-dev.yaml
make wait       # block until deployments/statefulsets roll out
make test       # run `helm test` (engine ready, gateway ready, smoke SQL, ...)
make cleanup    # uninstall release, delete PVCs, delete namespace (takes floci with it)
make delete     # kind delete cluster
```

`make dev` is the internal-Firebolt local-development path. It (1) applies `local-floci.yaml` to bring up a zero-auth S3 emulator and pre-create the engine's managed-storage bucket (the post-2026-05-13 metadata images refuse local-fs managed storage), (2) refreshes a 12-hour `regcred` Secret against the internal ECR pull-through cache, and (3) installs with `helm/values-dev.yaml` — which points engine + metadata at the ECR cache at the mutable `:dev` tag and wires `customEngineConfig.storage` at floci. Re-run `make dev` (or `make upgrade-dev`) before the ECR token expires.

For a plain install against the chart defaults (no overlay, no ECR secret, no floci — assumes you can pull `ghcr.io/firebolt-db/*` and have configured managed storage yourself):

```sh
make install     # helm install firebolt ./helm
# or, fully manual:
helm install firebolt ./helm --namespace firebolt --create-namespace -f my-values.yaml
```

## How it works

The Envoy gateway extracts the `X-Firebolt-Engine` header via a Lua filter and rewrites the upstream to the matching engine Service. Pensieve coordinates engine registration and reconciles against the `customEngineConfig.account_id` you configure. PostgreSQL is bundled by default for development; production deployments should set `postgresql.local_enabled: false` and provide an external database.

## Where to go next

- The full configuration reference is generated from `helm/values.yaml` and lives at [`helm/README.md`](./helm/README.md).
- For implementation detail, conventions, and rules for making changes to this repo, see [`AGENTS.md`](AGENTS.md). Module-specific details for the chart itself live in [`helm/AGENTS.md`](helm/AGENTS.md).
- Changelog: [`helm/CHANGELOG.md`](./helm/CHANGELOG.md).
- Security policy: [`SECURITY.md`](./SECURITY.md).
