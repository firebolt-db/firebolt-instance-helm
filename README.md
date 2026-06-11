# firebolt-instance-helm

Helm chart for running a Firebolt instance on Kubernetes: Envoy gateway, Metadata Service, PostgreSQL, and one or more Firebolt query engine StatefulSets.

The chart is published as `firebolt-instance` to `oci://ghcr.io/firebolt-db/helm-charts` on every change to `helm/` merged to `main`.

## Documentation
For more detailed information checkout our [official documentation](https://docs.firebolt.io/self-managed/helm-chart/overview)

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
- Prefer the repo's existing make targets and example manifests over hand-rolled kubectl/helm commands. Inspect the Makefile and use: `make create` (kind cluster), `make floci` (object storage emulator + bucket), then install. To install, use `make dev` (it wires the floci storage overlay and pins engine/metadata to the `:dev` tag); otherwise run `helm install` with your own values file that points customEngineConfig.storage at the floci endpoint, as shown in Quick start. Stream the output and stop on the first error.
- Poll for readiness with short loops; never sleep blindly. Wait for the floci deployment and bucket Job, then for the gateway, metadata, PostgreSQL, and engine pods/StatefulSets to become Ready (`kubectl get pods -n firebolt`, `kubectl rollout status`).
- After everything is up, run a smoke check with `make test`, which runs `helm test` (engine ready, gateway ready, smoke SQL, ...). Also confirm with `kubectl get pods,statefulset,svc -n firebolt`.
- When done, report the kube-context, what was deployed and where, the in-cluster gateway Service endpoint and the X-Firebolt-Engine header model for reaching a specific engine, and any remaining manual steps or warnings. If anything failed, show the failing command output and your best diagnosis before continuing.
- For teardown, use `make cleanup` (uninstall + delete PVCs + delete namespace) and `make delete` (delete the kind cluster).
```

This is the fast path if you want the agent to drive the install for you. If you would rather run the steps yourself, continue with the [Quick start](#quick-start) below.

## Quick start

For a step-by-step walkthrough, follow the quickstart guide in our [official documentation](https://docs.firebolt.io/self-managed/helm-chart/quickstart) or using the documentation source file at [`docs/quickstart.mdx`](docs/quickstart.mdx).

## Where to go next
- The full **configuration reference** is generated from `helm/values.yaml` and lives at [`helm/README.md`](./helm/README.md).
- Changelog: [`helm/CHANGELOG.md`](./helm/CHANGELOG.md).
- For **contributor** detail, conventions, and rules for making changes to this repo, see [`AGENTS.md`](AGENTS.md). Module-specific rules for the chart itself live in [`helm/AGENTS.md`](helm/AGENTS.md).
- Security policy: [`SECURITY.md`](./SECURITY.md).
