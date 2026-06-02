# Local development

`make dev` is the internal-Firebolt inner-loop install: engine and metadata pulled at the mutable `:dev` tag through the ECR pull-through cache, with floci standing in for managed-storage S3. External users want plain [`make install`](../docs/usage/single-engine.mdx).

## Prerequisites

- AWS credentials with `ecr:GetAuthorizationToken` for account `000000000000` (e.g. via `aws sso login`).
- A Kubernetes cluster the kubelet can reach the ECR pull-through cache from.

## Install

```bash
make create     # skip if you already have a cluster
make dev
make test
```

`make dev` runs `make floci` first (applies `local-floci.yaml`, waits for the bucket-create Job), refreshes the 12-hour `regcred` ECR pull secret, and installs the chart with `helm/values-dev.yaml`.

## Upgrade

| Install | Upgrade |
| --- | --- |
| `make install` | `make upgrade` |
| `make dev` | `make upgrade-dev` |

`make upgrade-dev` does not refresh the ECR secret. Re-run `make dev` (idempotent) when the 12-hour token expires.

## Why floci

The metadata images shipped after 2026-05-13 refuse local-filesystem managed storage in dedicated-Pensieve mode. `values-dev.yaml` sets `customEngineConfig.storage` to `type: minio`, which hardcodes the S3 access/secret to `firebolt/firebolt` — floci (zero-auth) signs through without any env-var plumbing.

## Reset floci

`make cleanup` deletes the namespace and floci with it. For a mid-session reset without uninstalling the chart:

```bash
kubectl delete -f local-floci.yaml -n firebolt
make floci
```

floci stores data in the pod's ephemeral filesystem (no PVC), so a pod restart wipes state.
