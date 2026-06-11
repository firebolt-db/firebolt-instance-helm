# firebolt-instance-helm

Helm chart for running a Firebolt instance on Kubernetes: Envoy gateway, Metadata Service, PostgreSQL, and one or more Firebolt query engine StatefulSets.

The chart is published as `firebolt-instance` to `oci://ghcr.io/firebolt-db/helm-charts` on every change to `helm/` merged to `main`.

## Scope

The chart deploys a complete Firebolt instance — gateway, metadata, PostgreSQL, engines — into any Kubernetes cluster. For day-2 operational capabilities (zero-downtime engine rollouts, autoscaling, drift correction, reusable per-engine templates), use the [Firebolt Kubernetes Operator](docs/operator-upgrade-path.mdx). See [`docs/`](docs/) for usage patterns.

## Architecture

```text
        client ── HTTP ──▶  ┌────────────────────┐
                            │       Gateway      │
                            └─────────┬──────────┘
                                      │ routes by X-Firebolt-Engine
                                      ▼
                            ┌────────────────────┐      ┌────────────────┐
                            │      Engine        │ ───▶ │ Object Storage │
                            │  StatefulSet(s)    │      └────────────────┘
                            └─────────┬──────────┘
                                      ▼
                            ┌────────────────────┐
                            │  Metadata Service  │
                            └─────────┬──────────┘
                                      │
                                      ▼
                                  PostgreSQL
```

Each entry under `engines:` becomes one 1-replica StatefulSet per node plus a shared headless Service, ClusterIP Service, and ConfigMap.

## Use this with a coding agent

Paste the following prompt into your favorite coding agent and let it drive the whole local install for you. Ours is Claude Code.

```text
Bring up a working Firebolt instance from this Helm chart on a local Kind cluster, end to end: gateway, metadata service, PostgreSQL, and at least one query engine StatefulSet.

If I only gave you the GitHub repo URL, clone the repo first. If I already opened the repo locally, work from the existing checkout.

Follow the "Quick start" section of README.md and the docs under docs/ (especially docs/prerequisites.mdx, docs/usage/single-engine.mdx, and docs/usage/object-storage/amazon-s3.mdx). Treat this as a request to actually deploy and verify the chart, not just inspect it. Don't assume my prerequisites are done; if a required tool is missing or a step is ambiguous, tell me and stop rather than guessing.

Key facts about this chart:
- Engines do NOT start without object storage. Every engine needs customEngineConfig.storage configured. Locally this is provided by the bundled floci S3 emulator via `make floci`, which also creates the managed_storage bucket.
- The Envoy gateway routes requests to engines by the X-Firebolt-Engine header (a Lua filter rewrites the upstream to the matching engine Service). Each entry under engines: becomes a 1-replica StatefulSet per node.
- PostgreSQL is bundled by default for local dev.

Workflow:
- Run a non-mutating discovery step first: print tool versions (docker, kind, kubectl, helm), Docker daemon status, any existing Kind clusters, and the current kube-context. Fail fast with a clear message if a required tool is missing or Docker is down.
- Before making any cluster changes, show me the resolved plan: which Kind cluster you will create or reuse, which make targets you will run, the namespace (default: firebolt), and which values file you will install with (it must set customEngineConfig.storage).
- Prefer the repo's existing make targets and example manifests over hand-rolled kubectl/helm commands. Inspect the Makefile and use: `make create` (kind cluster), `make floci` (object storage emulator + bucket), then install. To install, use `make dev` if you have Firebolt ECR access (it wires the floci storage overlay and an ECR pull secret); otherwise run `helm install` with your own values file that points customEngineConfig.storage at the floci endpoint, as shown in Quick start. Stream the output and stop on the first error.
- Poll for readiness with short loops; never sleep blindly. Wait for the floci deployment and bucket Job, then for the gateway, metadata, PostgreSQL, and engine pods/StatefulSets to become Ready (`kubectl get pods -n firebolt`, `kubectl rollout status`).
- After everything is up, run a smoke check with `make test`, which runs `helm test` (engine ready, gateway ready, smoke SQL, ...). Also confirm with `kubectl get pods,statefulset,svc -n firebolt`.
- When done, report the kube-context, what was deployed and where, the in-cluster gateway Service endpoint and the X-Firebolt-Engine header model for reaching a specific engine, and any remaining manual steps or warnings. If anything failed, show the failing command output and your best diagnosis before continuing.
- For teardown, use `make cleanup` (uninstall + delete PVCs + delete namespace) and `make delete` (delete the kind cluster).
```

This is the fast path if you want the agent to drive the install for you. If you would rather run the steps yourself, continue with the [Quick start](#quick-start) below.

## Quick start

Engines need object storage to become ready. This flow uses the bundled [floci](https://github.com/floci-io/floci) S3 emulator (`local-floci.yaml`) for a self-contained local install. For a real bucket, see [`docs/usage/object-storage/amazon-s3.mdx`](docs/usage/object-storage/amazon-s3.mdx).

Point the engine at floci with a values file:

```yaml
# my-values.yaml
customEngineConfig:
  storage:
    type: minio
    api_scheme: "s3://"
    bucket_name: firebolt-managed
    minio:
      endpoint: http://floci.firebolt.svc.cluster.local:4566
```

Then create the cluster, deploy storage, and install the chart:

```sh
make create                                # kind create cluster
make floci                                 # deploy the floci S3 emulator + create the bucket
helm install firebolt ./helm \
  --namespace firebolt --create-namespace \
  -f my-values.yaml
make test                                  # helm test (engine ready, gateway ready, smoke SQL)
make cleanup                               # uninstall release, delete PVCs, delete namespace
make delete                                # kind delete cluster
```

See [`docs/quickstart.mdx`](docs/quickstart.mdx) for a step-by-step walkthrough, [`docs/usage/single-engine.mdx`](docs/usage/single-engine.mdx) for install details, [`docs/prerequisites.mdx`](docs/prerequisites.mdx) for cluster requirements, and [`docs/`](docs/) for additional patterns (multi-engine, external PostgreSQL, image overrides).

## How it works

The Envoy gateway extracts the `X-Firebolt-Engine` header via a Lua filter and rewrites the upstream to the matching engine Service. The metadata service serves table-and-engine metadata to engines over gRPC, scoped to the `customEngineConfig.instance.id` ULID. PostgreSQL is bundled by default for development; production deployments should set `postgresql.local_enabled: false` and provide an external database.

## Where to go next

- **User-facing docs** are under [`docs/`](docs/), authored as Mintlify MDX with navigation in [`docs/docs.json`](docs/docs.json): [overview](docs/overview.mdx), [prerequisites](docs/prerequisites.mdx), [quickstart](docs/quickstart.mdx), usage patterns ([single engine](docs/usage/single-engine.mdx), [multi-engine](docs/usage/multi-engine.mdx), Object Storage ([Amazon S3](docs/usage/object-storage/amazon-s3.mdx), [Google Cloud Storage](docs/usage/object-storage/google-cloud-storage.mdx), [Azure Blob Storage](docs/usage/object-storage/azure-blob-storage.mdx)), [external PostgreSQL](docs/usage/external-postgres.mdx), [image overrides](docs/usage/image-overrides.mdx)), the [operator upgrade path](docs/operator-upgrade-path.mdx), and [troubleshooting](docs/troubleshooting.mdx).
- The full **configuration reference** is generated from `helm/values.yaml` and lives at [`helm/README.md`](./helm/README.md).
- For **contributor** detail, conventions, and rules for making changes to this repo, see [`AGENTS.md`](AGENTS.md). Module-specific rules for the chart itself live in [`helm/AGENTS.md`](helm/AGENTS.md).
- Changelog: [`helm/CHANGELOG.md`](./helm/CHANGELOG.md).
- Security policy: [`SECURITY.md`](./SECURITY.md).
