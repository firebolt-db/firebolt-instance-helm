# Local development

`make dev` is the inner-loop install: it pins engine and metadata to the mutable `:dev` tag (instead of the pinned `appVersion` that `make install` uses), pulls both images from GHCR, and uses floci for managed-storage S3. For a reproducible install at the chart's pinned `appVersion`, use plain [`make install`](../docs/usage/single-engine.mdx).

## Prerequisites

- A Kubernetes cluster (`make create` spins up a local kind cluster).

## Install

```bash
make create     # skip if you already have a cluster
make dev
make test
```

`make dev` runs `make floci` first (applies `local-floci.yaml`, waits for the bucket-create Job), then installs the chart with `helm/values-dev.yaml`.

## Upgrade

| Install | Upgrade |
| --- | --- |
| `make install` | `make upgrade` |
| `make dev` | `make upgrade-dev` |

## Why floci
The metadata images shipped after 2026-05-13 refuse local-filesystem managed storage in dedicated-Pensieve mode. `values-dev.yaml` points `customEngineConfig.storage` at floci (`managed_table_storage: s3` plus `aws.endpoint`) so local installs use object storage without cloud infrastructure. floci is zero-auth, so any signed request passes without the need to set up (dummy) AWS credentials.

## Reset floci

`make cleanup` deletes the namespace and floci with it. For a mid-session reset without uninstalling the chart:

```bash
kubectl delete -f local-floci.yaml -n firebolt
make floci
```

floci stores data in the pod's ephemeral filesystem (no PVC), so a pod restart wipes state.
