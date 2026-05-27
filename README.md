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
make install    # create namespace, refresh ECR pull secret, helm install
make wait       # block until deployments/statefulsets roll out
make test       # run `helm test` (engine ready, gateway ready, smoke SQL, ...)
make cleanup    # uninstall release, delete PVCs, delete namespace
make delete     # kind delete cluster
```

`make install` refreshes a `regcred` docker-registry Secret in the target namespace; the token is valid for 12 hours, so re-run `make install` (or `make upgrade`) before it expires. The chart's default image registry is `ghcr.io/firebolt-db`; the local install flow targets the internal Firebolt ECR via `helm/values.local.yaml`.

To install without the local kind / pull-secret glue:

```sh
helm install firebolt ./helm \
  --namespace firebolt --create-namespace \
  -f my-values.yaml
```

To track current-of-mainline engine and metadata builds rather than the pinned `appVersion`, layer `helm/values-dev.yaml` on top of your values — it flips both image tags to the mutable `:dev` alias:

```sh
helm install firebolt ./helm -f my-values.yaml -f helm/values-dev.yaml
# or:
make install VALUES_FILE=helm/values-dev.yaml
```

## How it works

The Envoy gateway extracts the `X-Firebolt-Engine` header via a Lua filter and rewrites the upstream to the matching engine Service. Pensieve coordinates engine registration and reconciles against the `customEngineConfig.account_id` you configure. PostgreSQL is bundled by default for development; production deployments should set `postgresql.local_enabled: false` and provide an external database.

## Where to go next

- The full configuration reference is generated from `helm/values.yaml` and lives at [`helm/README.md`](./helm/README.md).
- For implementation detail, conventions, and rules for making changes to this repo, see [`AGENTS.md`](AGENTS.md). Module-specific details for the chart itself live in [`helm/AGENTS.md`](helm/AGENTS.md).
- Changelog: [`helm/CHANGELOG.md`](./helm/CHANGELOG.md).
- Security policy: [`SECURITY.md`](./SECURITY.md).
