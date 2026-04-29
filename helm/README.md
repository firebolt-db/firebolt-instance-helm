# firebolt-instance

![Version: 0.5.8](https://img.shields.io/badge/Version-0.5.8-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: debug-4.32.0-pre.0.20260428141824.5abdf30556cd](https://img.shields.io/badge/AppVersion-debug--4.32.0--pre.0.20260428141824.5abdf30556cd-informational?style=flat-square)

Firebolt Instance on Kubernetes — Envoy gateway, metadata, auth, and engines

**Homepage:** <https://github.com/firebolt-db/firebolt-instance-helm>

## Source Code

* <https://github.com/firebolt-db/firebolt-instance-helm>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| auth | object | {} | Authentication configuration for firebolt-core `auth.json`. Not enforced yet; reserved for future engine-level auth propagation. TODO: wire auth fields into Envoy config or engine auth once supported. |
| auth.local | object | {} | Local authentication configuration. Used when `mode: local`. |
| auth.local.credentialsSecretRef | string | `""` | Name of a Secret containing username/password or API keys. |
| auth.mode | string | `"none"` | Authentication mode. One of `none`, `local`, or `sso`. |
| auth.oidc | object | {} | OIDC/SSO configuration. Used when `mode: sso`. |
| auth.oidc.claimMappings | object | {} | Claim mappings for OIDC token fields. |
| auth.oidc.claimMappings.username | string | `"email"` | OIDC claim used as the username. |
| auth.oidc.clientID | string | `""` | OIDC client ID. |
| auth.oidc.issuerURL | string | `""` | OIDC issuer URL. |
| createNamespace | bool | `false` | When true, a Namespace resource is included in the chart output. Pair with `helm install --create-namespace --set createNamespace=false`. |
| customEngineConfig | object | {} | Custom configuration merged into each engine's `config.config` object. |
| customEngineConfig.account_id | string | `"01KP98J0000000000000000000"` | Account ID for the Firebolt instance. Must match the account reconciled by Dedicated Pensieve at startup (see `pensieve_lite.default_account_id`, which defaults to this ULID). |
| customEngineConfig.account_name | string | `"default-account"` | Account name for the Firebolt instance. |
| customEngineConfig.cluster_id | string | `"default-cluster"` | Cluster ID for the Firebolt instance. |
| customEngineConfig.logger_formatting | string | `"json"` | Logger output format. Use "json" for structured logging. |
| customEngineConfig.logger_use_files | bool | `false` | When false, logs are written to stdout only (no file output). |
| customEngineConfig.organization_id | string | `"01KP98J0000000000000000001"` | Organization ID for the Firebolt instance. |
| customEngineConfig.organization_name | string | `"default-org"` | Organization name for the Firebolt instance. |
| engineSpec | object | {} | Shared engine pod defaults applied to all engines unless overridden per-engine. |
| engineSpec.affinity | object | `{}` | Affinity rules for engine pod scheduling. |
| engineSpec.customInitContainersTemplate | list | `[]` | Custom init containers injected into engine pods (supports templating). |
| engineSpec.customVolumes | list | `[]` | Custom volumes injected into engine pods. |
| engineSpec.defaultStorage | object | {} | Default PVC storage spec for engines. `storageClassName` is intentionally absent — the cluster default storage class is used. Override here or per-engine to specify a class (e.g. `storageClassName: gp3`). |
| engineSpec.defaultStorage.accessModes | list | `["ReadWriteOnce"]` | Access modes for the default PVC. |
| engineSpec.defaultStorage.resources.requests.storage | string | `"100Gi"` | Default storage size for engine PVCs. |
| engineSpec.hostPathStorageEnabled | bool | `false` | When true, uses hostPath instead of PVC for engine data. |
| engineSpec.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| engineSpec.image.repository | string | `"ghcr.io/firebolt-db/firebolt-db"` | Container repository for the firebolt-core engine image. |
| engineSpec.image.tag | string | `""` | Image tag. Defaults to `Chart.appVersion` when empty. |
| engineSpec.memlockSetup | bool | `false` | When true, a memlock-setup init container is added to configure memory locking limits. |
| engineSpec.nodeHostSuffix | string | `".cluster.local"` | Suffix appended after `.svc` in node FQDNs in `config.json`. |
| engineSpec.nodeSelector | object | `{}` | Node selector for engine pod scheduling. |
| engineSpec.podSecurityContext | object | {} | Pod-level security context for engine pods. |
| engineSpec.podSecurityContext.fsGroup | int | `3473` | Group applied to mounted volumes. Matches the engine UID/GID so the data PVC is chowned on mount. |
| engineSpec.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` | When to re-apply `fsGroup` ownership. `OnRootMismatch` skips the chown when already correct — much faster on large PVCs. |
| engineSpec.podSecurityContext.runAsNonRoot | bool | `true` | Reject the pod if any container runs as UID 0. Also gates the chart's container-level `runAs*` defaults, memlock init, and the entrypoint UID check. |
| engineSpec.readiness | bool | `true` | When true, a readiness probe is added to the core container. |
| engineSpec.serviceAccount | string | `"default"` | Service account name for engine pods. |
| engineSpec.storageHostPath | object | {} | Host path configuration used when `hostPathStorageEnabled` is true. |
| engineSpec.storageHostPath.path | string | `"/var/lib/firebolt-core"` | Host path for engine data. |
| engineSpec.storageHostPath.type | string | `"DirectoryOrCreate"` | Host path type. |
| engineSpec.terminationGracePeriodSeconds | int | `60` | Termination grace period in seconds for engine pods. Sized to give in-flight queries time to drain before SIGKILL during rolling updates and node drains. |
| engineSpec.tolerations | list | `[]` | Tolerations for engine pod scheduling. |
| engineSpec.uiSidecar | bool | `false` | Deploy a Core UI sidecar for each engine pod. |
| engines | list | [] | Engine definitions. Each entry produces one StatefulSet per node (`replicas` controls node count), plus a shared headless Service, ClusterIP Service, and ConfigMap. Per-engine values override the shared `engineSpec` defaults. |
| engines[0].affinity | object | `{}` | Affinity rules for engine pod scheduling. |
| engines[0].name | string | `"default"` | Engine name. Used to derive resource names across the chart. |
| engines[0].nodeSelector | object | `{}` | Node selector for engine pod scheduling. |
| engines[0].podAnnotations | object | `{}` | Annotations applied to engine pods. |
| engines[0].priorityClassName | string | `""` | Priority class name for engine pods. |
| engines[0].replicas | int | `1` | Number of nodes in this engine group (one StatefulSet replica per node). |
| engines[0].resources | object | `{"limits":{"memory":"4Gi"},"requests":{"cpu":"1","memory":"4Gi"}}` | Resource requests and limits for engine containers. Firebolt Core is memory-bound: more RAM directly improves cache hit rates and query throughput. CPU governs parallel query execution threads.  Typical sizing guidance:   Development / functional testing:  2 vCPU  /  8 Gi  (request)   Small production workload:         4 vCPU  / 32 Gi   Medium production workload:        8 vCPU  / 64 Gi   Large production workload:        16 vCPU  / 128 Gi  Storage I/O is also significant — use an SSD-backed StorageClass and size the PVC to hold your working dataset plus ~30 % headroom. |
| engines[0].storage | object | `{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"100Gi"}}}` | PVC storage configuration for this engine. Falls back to `engineSpec.defaultStorage` if omitted. |
| engines[0].tolerations | list | `[]` | Tolerations for engine pod scheduling. |
| extraLabels | object | `{"firebolt/product":"core"}` | Extra labels applied to all resources and pods. |
| gateway | object | {} | Envoy gateway proxy configuration. Routes queries to engine Services based on the `X-Firebolt-Engine` HTTP header. A Lua filter extracts the engine name and rewrites the upstream to `{engine}-service:3473` via dynamic forward proxy. |
| gateway.adminPort | int | `9901` | Envoy admin interface port (used for health checks). |
| gateway.containerPort | int | `8080` | Envoy listener port for client traffic. |
| gateway.enabled | bool | `true` | Set to true to deploy the Envoy gateway proxy. |
| gateway.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| gateway.image.repository | string | `"envoyproxy/envoy"` | Envoy proxy container image. |
| gateway.image.tag | string | `"v1.37.2"` | Envoy image tag. |
| gateway.metricsPort | int | `9090` | Container port that exposes Envoy Prometheus metrics (/stats/prometheus). A dedicated stats listener proxies requests to the Envoy admin on loopback. |
| gateway.pdb | object | {} | PodDisruptionBudget for gateway pods. Prevents node drains from evicting all replicas at once. |
| gateway.pdb.enabled | bool | `true` | Emit a PodDisruptionBudget for the gateway. Set to `false` when an external policy controller (Kyverno, OPA Gatekeeper, etc.) or a cluster-wide PDB tool already manages disruption budgets, so the chart's PDB does not conflict with theirs. |
| gateway.pdb.maxUnavailable | int | `1` | Maximum gateway pods that may be unavailable simultaneously during voluntary disruption. Mutually exclusive with `minAvailable` — set one and leave the other `null`. |
| gateway.pdb.minAvailable | string | `nil` | Minimum gateway pods that must remain available during voluntary disruption. Mutually exclusive with `maxUnavailable`. |
| gateway.podTemplate | object | `{}` | Pod template overrides for gateway pods (nodeSelector, tolerations, affinity). |
| gateway.replicas | int | `2` | Number of gateway replicas. |
| gateway.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits for the Envoy container. |
| gateway.service | object | {} | Gateway Service configuration. |
| gateway.service.port | int | `80` | External service port proxied to `containerPort`. |
| gateway.service.type | string | `"ClusterIP"` | Service type. One of `ClusterIP`, `LoadBalancer`, or `NodePort`. |
| imagePullSecrets | list | `[]` | Registry credentials. Must be a pre-created docker-registry Secret in the deployment namespace. Leave empty if nodes have ambient registry access (e.g. node IAM role). |
| metadata | object | {} | Metadata service (Pensieve) configuration. |
| metadata.deployment | object | {} | Deployment-level settings for the metadata service. |
| metadata.deployment.securityContext | object | `{}` | Pod-level security context. |
| metadata.deployment.terminationGracePeriodSeconds | int | `30` | Termination grace period in seconds. |
| metadata.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| metadata.image.repository | string | `"ghcr.io/firebolt-db/dedicated-pensieve"` | Container repository for the Pensieve metadata service image. |
| metadata.image.tag | string | `""` | Pensieve image tag. Defaults to `Chart.appVersion` (kept in lockstep with the engine) when empty. The template strips any `release-` or `debug-` prefix from `Chart.appVersion` when falling back, since the pensieve release pipeline tags images without that prefix. Override explicitly only when the metadata service must run a version other than the engine. |
| metadata.podTemplate | object | `{}` | Pod template overrides for the metadata service (nodeSelector, tolerations, affinity). |
| metadata.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` | Resource requests and limits for the metadata service container. Pensieve is a lightweight gRPC service; increase memory if you run many engines. |
| metadata.server | object | {} | gRPC server configuration for the metadata service. |
| metadata.server.host | string | `"0.0.0.0"` | gRPC server listen address. |
| metadata.server.log_level | string | `"information"` | Log level for the metadata service. |
| metadata.server.port | int | `7000` | gRPC server port. |
| metadata.server.threads | int | `0` | Number of server threads. `0` uses all available cores. |
| podMonitor | object | {} | PodMonitor configuration for Prometheus metrics scraping. Requires the Prometheus Operator CRDs to be installed. |
| podMonitor.engines | object | `{"enabled":false,"interval":"15s"}` | Create a PodMonitor for engine pods (port 9090, /metrics). |
| podMonitor.gateway | object | `{"enabled":false,"interval":"15s"}` | Create a PodMonitor for gateway pods (/stats/prometheus). |
| postgresql | object | {} | PostgreSQL configuration. When `local_enabled: true` the chart deploys a single-replica `postgres:16-alpine` StatefulSet. Set `local_enabled: false` and supply connection details for an external database. |
| postgresql.connect_timeout_sec | int | `5` | Connection timeout in seconds. |
| postgresql.credentials | object | {} | PostgreSQL credentials Secret configuration. |
| postgresql.credentials.existingSecret | string | `""` | Reference an externally-managed Secret (e.g. via ESO). When set, the chart will not create its own Secret. Ignored when `postgresql.local_enabled` is true. |
| postgresql.credentials.mountPath | string | `"/secrets/postgres"` | Mount path for the credentials Secret inside the metadata service container. |
| postgresql.database | string | `"firebolt_metadata"` | Database name. |
| postgresql.host | string | `""` | PostgreSQL host. Auto-derived when `local_enabled` is true; must be set explicitly for external databases. |
| postgresql.image | string | `"postgres:16-alpine"` | PostgreSQL image used for the bundled StatefulSet. |
| postgresql.keepalive | object | {} | TCP keepalive settings for the PostgreSQL connection. |
| postgresql.keepalive.count | int | `5` | Maximum number of keepalive probes before dropping the connection. |
| postgresql.keepalive.enabled | int | `1` | Enable TCP keepalive (`1` = enabled). |
| postgresql.keepalive.idle_sec | int | `120` | Keepalive idle time in seconds. |
| postgresql.keepalive.interval_sec | int | `30` | Keepalive probe interval in seconds. |
| postgresql.local_enabled | bool | `true` | When true, deploys a bundled PostgreSQL StatefulSet. Set to false to use an external database. |
| postgresql.password | string | `""` | Database password. Required when `local_enabled` is true. For external databases, set here or use `postgresql.credentials.existingSecret`. |
| postgresql.persistence | object | {} | Persistence configuration for the bundled PostgreSQL StatefulSet. |
| postgresql.persistence.size | string | `"10Gi"` | PVC size for bundled PostgreSQL data. |
| postgresql.port | int | `5432` | PostgreSQL port. |
| postgresql.resources | object | `{"limits":{"cpu":"250m","memory":"256Mi"},"requests":{"cpu":"25m","memory":"64Mi"}}` | Resource requests and limits for the bundled PostgreSQL container. |
| postgresql.schema | string | `"public"` | PostgreSQL schema. |
| postgresql.username | string | `"firebolt"` | Database username. |
| securityContextCapabilities | object | `{"drop":["ALL"]}` | Security context capabilities for engine containers. |
| utilitiesImage | string | `"debian:stable-slim"` | Image used for utility init/sidecar containers (e.g. the memlock-setup sidecar). |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
