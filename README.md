# firebolt-instance-helm

[![CI](https://img.shields.io/github/checks-status/firebolt-db/firebolt-instance-helm/main?label=CI)](https://github.com/firebolt-db/firebolt-instance-helm/actions?query=branch%3Amain)
[![Chart Version](https://img.shields.io/github/v/tag/firebolt-db/firebolt-instance-helm?label=chart&sort=semver)](https://github.com/firebolt-db/firebolt-instance-helm/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

Helm chart for running a Firebolt instance on Kubernetes: Envoy gateway, Pensieve
metadata service, PostgreSQL, and one or more query engine StatefulSets.

- Chart: [`helm/`](./helm) — published as `firebolt-instance`
- Generated values reference: [`helm/README.md`](./helm/README.md)
- Changelog: [`helm/CHANGELOG.md`](./helm/CHANGELOG.md)

## Prerequisites

- `kubectl` and `helm` (v3) on your `PATH`
- Access to a Kubernetes cluster. For local use, `kind` is enough
- The chart pulls `firebolt-core` and `dedicated-pensieve` from `ghcr.io/firebolt-db`
  by default. Override `engineSpec.image.repository` and `metadata.image.repository`
  to use a different registry.
- Optional, for contributors: `pre-commit`, `helm-docs`

## Quick start (local kind cluster)

The [`Makefile`](./Makefile) wraps the common flow. All targets honour
`RELEASE` (default `firebolt`) and `NAMESPACE` (default `firebolt`).

```sh
make create     # kind create cluster
make install    # create namespace, refresh ECR pull secret, helm install
make wait       # block until deployments/statefulsets roll out
make test       # run `helm test` (engine ready, gateway ready, smoke SQL, ...)
make cleanup    # uninstall release, delete PVCs, delete namespace
make delete     # kind delete cluster
```

`make install` does three things:

1. Ensures the target namespace exists.
2. Refreshes a `regcred` docker-registry Secret in that namespace using
   `aws ecr get-login-password`. Re-run `make install` (or `make upgrade`) before
   the 12-hour ECR token expires.
3. Runs `helm install $(RELEASE) ./helm -f helm/values.local.yaml`.

To push new configuration into a running release, edit `helm/values.local.yaml`
and run `make upgrade`.

### Custom values file or release name

```sh
make install  RELEASE=dev NAMESPACE=firebolt-dev VALUES_FILE=./my-values.yaml
make upgrade  RELEASE=dev NAMESPACE=firebolt-dev VALUES_FILE=./my-values.yaml
```

## Installing without the Makefile

If you do not want the ECR / kind glue, install the chart directly:

```sh
helm install firebolt ./helm \
  --namespace firebolt --create-namespace \
  -f my-values.yaml
```

When pulling from the Firebolt ECR you still need a pull secret in the
namespace; see `make install` for the one-liner, or provide your own and
reference it via `imagePullSecrets`.

## Configuration you will actually change

Full reference lives in [`helm/README.md`](./helm/README.md) (auto-generated
from [`helm/values.yaml`](./helm/values.yaml)). The knobs below cover the vast
majority of real deployments.

### Engine and metadata versioning

The chart ships a single `appVersion` in [`Chart.yaml`](./helm/Chart.yaml).
Both the engine image (`firebolt-core`) and the metadata image
(`dedicated-pensieve`) default to that tag, which keeps them in lockstep.
Override only when you need to pin.

```yaml
# Pin the engine to a specific firebolt-core build.
engineSpec:
  image:
    tag: release-4.32.0

# Usually leave blank so it tracks the engine via Chart.appVersion.
# The chart strips any `release-` / `debug-` prefix before using it as the
# pensieve tag, because pensieve publishes without that prefix.
metadata:
  image:
    tag: ""
```

Other image tags worth knowing:

- `gateway.image.tag` — Envoy version (default `v1.37.2`).
- `postgresql.image` — bundled Postgres image (default `postgres:16-alpine`).
- `utilitiesImage` — base image for init/sidecar helpers (default `debian:stable-slim`).

### Engines: sizing, replicas, storage

Each entry in `engines:` becomes its own StatefulSet, headless Service,
ClusterIP Service, and ConfigMap. `replicas` is the node count for that engine
group. Per-engine values override `engineSpec` defaults.

```yaml
engines:
  - name: default
    replicas: 1               # nodes in this engine
    resources:
      requests: { cpu: "4", memory: "32Gi" }
      limits:   { memory: "32Gi" }
    storage:
      accessModes: [ReadWriteOnce]
      storageClassName: gp3   # omit to use the cluster default
      resources:
        requests:
          storage: 500Gi
  - name: analytics
    replicas: 3
    resources:
      requests: { cpu: "8", memory: "64Gi" }
      limits:   { memory: "64Gi" }
```

Sizing guidance (from `values.yaml`):

| Workload                       | CPU request | Memory request |
| ------------------------------ | ----------- | -------------- |
| Dev / functional testing       | 2 vCPU      | 8 Gi           |
| Small production               | 4 vCPU      | 32 Gi          |
| Medium production              | 8 vCPU      | 64 Gi          |
| Large production               | 16 vCPU     | 128 Gi         |

Firebolt Core is memory-bound — prioritise RAM. Storage I/O also matters; use
an SSD-backed StorageClass and size the PVC to your working set plus ~30 %
headroom.

### Gateway exposure

Envoy routes queries to the correct engine based on the `X-Firebolt-Engine`
header. By default it is `ClusterIP`; expose it externally when you need it:

```yaml
gateway:
  service:
    type: LoadBalancer        # or NodePort
    port: 80
  replicas: 2
```

### PostgreSQL: bundled vs external

Default is a bundled single-replica `postgres:16-alpine` StatefulSet — fine for
dev, not for production. For an external database:

```yaml
postgresql:
  local_enabled: false
  host: my-postgres.internal
  port: 5432
  database: firebolt_metadata
  username: firebolt
  credentials:
    existingSecret: firebolt-postgres-creds   # managed by ESO, etc.
```

If you keep the bundled DB, set `postgresql.password` — it is required.

### Pull secrets

Leave `imagePullSecrets` empty if your nodes have ambient ECR access (node IAM
role, IRSA, etc.). Otherwise reference a pre-created `docker-registry` Secret:

```yaml
imagePullSecrets:
  - name: regcred
```

`make install` creates `regcred` for you; [`helm/values.local.yaml`](./helm/values.local.yaml)
is already wired to use it.

### Identity

`customNodeConfig.account_id` must match the account Pensieve reconciles at
startup. The defaults shipped in [`values.yaml`](./helm/values.yaml) work
out-of-the-box; override together if you change them.

### Observability

```yaml
podMonitor:
  engines:
    enabled: true             # requires the Prometheus Operator CRDs
  gateway:
    enabled: true
```

## Testing

The chart ships `helm test` hooks under `helm/templates/tests/` covering DNS,
engine/gateway readiness, metadata service, Postgres, and a smoke SQL query.

```sh
make test           # helm test $(RELEASE) --namespace $(NAMESPACE) --logs
make test-cleanup   # delete leftover $(RELEASE)-test-* pods
```

## Development

```sh
make setup-pre-commit    # install pre-commit hooks (needs pre-commit + helm-docs)
make lint                # helm lint --strict + helm template dry-run
make docs                # regenerate helm/README.md from values.yaml
```

`helm/README.md` is generated — edit the descriptions in
[`helm/values.yaml`](./helm/values.yaml) and run `make docs` instead of editing
the README directly.

## License

See [`LICENSE`](./LICENSE).
