# firebolt-instance

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: release-5.0.1-0.20260713060957.513515666721](https://img.shields.io/badge/AppVersion-release--5.0.1--0.20260713060957.513515666721-informational?style=flat-square)

Firebolt Instance on Kubernetes — Envoy gateway, metadata, auth, and engines

**Homepage:** <https://github.com/firebolt-db/firebolt-instance-helm>

## Source Code

* <https://github.com/firebolt-db/firebolt-instance-helm>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| auth | object | {} | Authentication configuration for the Firebolt engine, rendered into the engine's `config.yaml` under `instance.auth`. When `enabled` is false, nothing is rendered under `instance.auth` — the engine refuses to start if `admin` or `oidc` are present while auth is disabled. Everything beyond the admin account and signing keys (OIDC providers, `password_login`, `jwt.*`, JIT provisioning, `preferred_authorization_server`) is not a first-class value here — set it under `customEngineConfig.instance.auth`, which is deep-merged on top of the block this chart renders. |
| auth.admin | object | {} | Bootstrap administrator account (`instance.auth.admin`). Required when `auth.enabled` is true. |
| auth.admin.name | string | `"firebolt"` | Admin username (`instance.auth.admin.name`). |
| auth.admin.password | object | {} | Admin password source. The chart only accepts an existing Secret — there is no literal-password value or certManager option (a password isn't a certificate), so enabling auth always requires a Secret to already exist. |
| auth.admin.password.existingSecret | object | {} | Existing Secret containing the admin password under key `password`. Mounted read-only and passed to the engine as `password_file`. |
| auth.admin.password.existingSecret.secretRef | string | `""` | Secret name. |
| auth.enabled | bool | `false` | Enable authentication on the engine (`instance.auth.enabled`). |
| auth.signingKeys | list | [] | JWT signing keys for the engine's embedded Authorization Server (`instance.auth.local.signing_keys`). An ordered list: the **first** entry is the active signer used for new tokens; every entry remains valid for verifying tokens already issued under it. **To rotate the signing key, prepend a new entry** rather than replacing the list, so tokens signed by the outgoing key keep validating until it's removed. At least one entry is required when `auth.enabled` is true — an engine with no explicit signing key falls back to a per-pod dev key that differs across nodes and breaks token validation in a multi-node engine.  Each entry sets exactly one of `existingSecret` / `certManager`:   - `id` — key identifier, published as the JWT `kid` header     (`instance.auth.local.signing_keys[].id`).   - `existingSecret.secretRef` — Secret containing the PEM private key     under key `tls.key`.   - `certManager` — a chart-rendered cert-manager `Certificate` request     (`algorithm`, `size`, `issuerRef.{name,kind}`). Requires cert-manager     and its CRDs installed in-cluster. The chart pins     `privateKey.rotationPolicy: Never` so cert-manager never silently     rotates a key out from under already-issued tokens — rotate by     prepending a new list entry instead. |
| createNamespace | bool | `false` | When true, a Namespace resource is included in the chart output. Pair with `helm install --create-namespace --set createNamespace=false`. |
| customEngineConfig | object | {} | Custom engine configuration deep-merged into the rendered engine config.yaml at the root. The rendered document follows the Firebolt Core configuration schema (`schema_version: "1.0"`); user-supplied keys at the top of `customEngineConfig` become siblings of the chart-managed `engine:` and `instance:` blocks (e.g. `logging:`), and keys nested under `instance:` merge into the instance block (e.g. `instance.id`, or `instance.auth.*` alongside the admin account and signing keys the `auth` value block below renders when `auth.enabled` is true — see `auth` for what belongs there instead of here).  Chart-authoritative paths are silently stripped from this input and cannot be overridden: `schema_version`, `engine.id`, `engine.nodes`, `engine.termination_grace_period`, `instance.type`, `instance.multi_engine`, and — only while `auth.enabled` / `tls.engine.enabled` are actually rendering them — `instance.auth.{enabled,admin,local.signing_keys}` and `endpoints.http.listeners`. |
| customEngineConfig.instance | object | {} | Instance identity. `id` propagates internally to `account_id`, `account_name`, `organization_id`, and `organization_name`, so the chart only needs to set the ULID once. |
| customEngineConfig.instance.id | string | `"01KP98J0000000000000000000"` | ULID for the Firebolt instance. Must match the account reconciled by the metadata service at startup. |
| engineSpec | object | {} | Shared engine pod defaults applied to all engines unless overridden per-engine. |
| engineSpec.affinity | object | `{}` | Affinity rules for engine pod scheduling. |
| engineSpec.customInitContainersTemplate | list | `[]` | Custom init containers injected into engine pods (supports templating). |
| engineSpec.customVolumeMounts | list | `[]` | Custom volume mounts injected into the engine `core` container, paired with `customVolumes` above — a volume declared there is inert until also mounted here. |
| engineSpec.customVolumes | list | `[]` | Custom volumes injected into engine pods. |
| engineSpec.defaultStorage | object | {} | Default PVC storage spec for engines. `storageClassName` is intentionally absent — the cluster default storage class is used. Override here or per-engine to specify a class (e.g. `storageClassName: gp3`). |
| engineSpec.defaultStorage.accessModes | list | `["ReadWriteOnce"]` | Access modes for the default PVC. |
| engineSpec.defaultStorage.resources.requests.storage | string | `"100Gi"` | Default storage size for engine PVCs. |
| engineSpec.extraEnv | list | [] | Extra environment variables for the engine container. Use this to inject AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (for example via `valueFrom.secretKeyRef`) for a custom S3-compatible store (`managed_table_storage: s3` + `aws.endpoint`). |
| engineSpec.extraEnvFrom | list | [] | Extra `envFrom` sources for the engine container. Use a `secretRef` to load a Secret holding AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY for a custom S3-compatible store. |
| engineSpec.hostPathStorageEnabled | bool | `false` | When true, uses hostPath instead of PVC for engine data. |
| engineSpec.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| engineSpec.image.repository | string | `"ghcr.io/firebolt-db/engine"` | Container repository for the Firebolt engine image. |
| engineSpec.image.tag | string | `""` | Image tag. Defaults to `Chart.appVersion` when empty. |
| engineSpec.memlockSetup | bool | `false` | When true, a memlock-setup init container is added to configure memory locking limits. |
| engineSpec.nodeHostSuffix | string | `".cluster.local"` | Suffix appended after `.svc` in node FQDNs in `config.yaml`. |
| engineSpec.nodeSelector | object | `{}` | Node selector for engine pod scheduling. |
| engineSpec.podSecurityContext | object | {} | Pod-level security context for engine pods. |
| engineSpec.podSecurityContext.fsGroup | int | `3473` | Group applied to mounted volumes. Matches the engine UID/GID so the data PVC is chowned on mount. |
| engineSpec.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` | When to re-apply `fsGroup` ownership. `OnRootMismatch` skips the chown when already correct — much faster on large PVCs. |
| engineSpec.podSecurityContext.runAsNonRoot | bool | `true` | Reject the pod if any container runs as UID 0. Also gates the chart's container-level `runAs*` defaults, memlock init, and the entrypoint UID check. |
| engineSpec.readiness | bool | `true` | When true, a readiness probe is added to the core container. |
| engineSpec.serviceAccount | string | `""` | ServiceAccount used by engine pods.  Empty (the default): the chart creates `<release>-engine` with `automountServiceAccountToken: false`, so a code-execution exploit in the engine container has no SA token to talk to the apiserver with. Engines do not call the Kubernetes API; the dedicated SA replaces the namespace `default` SA, which automounts a token and inherits any RoleBindings accumulated on `default` from unrelated installs.  Non-empty: the chart references the named SA verbatim and does NOT create one — bring your own (the documented IRSA / Pod Identity flow at docs/usage/object-storage/amazon-s3.mdx works this way). The chart cannot influence `automountServiceAccountToken` on a SA it does not own; set it explicitly in your SA manifest if you want the same hardening. |
| engineSpec.storageHostPath | object | {} | Host path configuration used when `hostPathStorageEnabled` is true. |
| engineSpec.storageHostPath.path | string | `"/var/lib/firebolt-core"` | Host path for engine data. |
| engineSpec.storageHostPath.type | string | `"DirectoryOrCreate"` | Host path type. |
| engineSpec.terminationGracePeriodSeconds | int | `60` | Termination grace period in seconds for engine pods. Sized to give in-flight queries time to drain before SIGKILL during rolling updates and node drains. Also rendered into the engine `config.yaml` as `engine.termination_grace_period` with a 5s safety margin (floored at 1s), so the engine's own in-flight-query wait stays below this value. |
| engineSpec.tolerations | list | `[]` | Tolerations for engine pod scheduling. |
| engineSpec.topologySpreadConstraints | list | `[]` | Topology spread constraints for engine pod scheduling. Set this to force zone or node spread across an engine's nodes so a single zone or node failure cannot take down the whole engine. Overridable per-engine via `engines[].topologySpreadConstraints`. |
| engineSpec.uiSidecar | bool | `false` | Deploy a Core UI sidecar for each engine pod. |
| engines | list | [] | Engine definitions. Each entry produces one StatefulSet per node (`replicas` controls node count), plus a shared headless Service, ClusterIP Service, and ConfigMap. Per-engine values override the shared `engineSpec` defaults. |
| engines[0].affinity | object | `{}` | Affinity rules for engine pod scheduling. |
| engines[0].name | string | `"default"` | Engine name. Used to derive resource names across the chart. |
| engines[0].nodeSelector | object | `{}` | Node selector for engine pod scheduling. |
| engines[0].podAnnotations | object | `{}` | Annotations applied to engine pods. |
| engines[0].podLabels | object | `{}` | Extra labels applied to this engine's pod template. Chart-reserved keys (`app.kubernetes.io/{name,instance,managed-by}` and `firebolt/{component,engine,node}`) are silently dropped from user input so the StatefulSet selector cannot be detached by a typo. |
| engines[0].priorityClassName | string | `""` | Priority class name for engine pods. |
| engines[0].replicas | int | `1` | Number of nodes in this engine group (one StatefulSet replica per node). |
| engines[0].resources | object | `{"limits":{"memory":"4Gi"},"requests":{"cpu":"1","memory":"4Gi"}}` | Resource requests and limits for engine containers. Firebolt Core is memory-bound: more RAM directly improves cache hit rates and query throughput. CPU governs parallel query execution threads.  Typical sizing guidance:   Development / functional testing:  2 vCPU  /  8 Gi  (request)   Small production workload:         4 vCPU  / 32 Gi   Medium production workload:        8 vCPU  / 64 Gi   Large production workload:        16 vCPU  / 128 Gi  Storage I/O is also significant — use an SSD-backed StorageClass and size the PVC to hold your working dataset plus ~30 % headroom. |
| engines[0].storage | object | `{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"100Gi"}}}` | PVC storage configuration for this engine. Falls back to `engineSpec.defaultStorage` if omitted. |
| engines[0].tolerations | list | `[]` | Tolerations for engine pod scheduling. |
| engines[0].topologySpreadConstraints | list | `[]` | Topology spread constraints for engine pod scheduling. Overrides `engineSpec.topologySpreadConstraints` for this engine when set. |
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
| gateway.podTemplate | object | {} | Pod template overrides for gateway pods. Only the keys listed below are read by the chart; arbitrary [PodSpec](https://pkg.go.dev/k8s.io/api/core/v1#PodSpec) fields supplied here are silently ignored. Overrides are additive and do not lower the chart's security floor: the gateway container keeps its non-root, drop-ALL-capabilities default `securityContext` unless you explicitly replace it via `securityContext` below. |
| gateway.podTemplate.affinity | object | `{}` | Affinity rules for gateway pod scheduling. |
| gateway.podTemplate.envFrom | list | `[]` | `envFrom` sources (ConfigMap/Secret) for the Envoy container. |
| gateway.podTemplate.extraPodLabels | object | `{}` | Extra labels applied to the gateway pod template. Chart-managed selector / component labels cannot be overridden. |
| gateway.podTemplate.imagePullSecrets | list | `[]` | Per-component image pull secrets, concatenated with the top-level `imagePullSecrets`. |
| gateway.podTemplate.initContainers | list | `[]` | Init containers injected into the gateway pod. |
| gateway.podTemplate.lifecycle | object | {} | Lifecycle hooks for the Envoy container. When empty, the chart keeps its default `preStop` drain hook; setting this replaces that hook, so preserve an equivalent drain step if you override it. |
| gateway.podTemplate.nodeSelector | object | `{}` | Node selector for gateway pod scheduling. |
| gateway.podTemplate.podAnnotations | object | `{}` | Extra annotations applied to the gateway pod template. Merged with the chart-managed checksum annotation. |
| gateway.podTemplate.podSecurityContext | object | {} | Pod-level security context override for the gateway pod. When empty, no pod-level securityContext is set. Setting this does not relax the container-level hardening unless you also override `securityContext`. |
| gateway.podTemplate.priorityClassName | string | `""` | Pod priority class. Reference a `PriorityClass` to let the gateway preempt lower-priority workloads when the cluster is under resource pressure — useful when query routing must stay up during incidents. |
| gateway.podTemplate.securityContext | object | {} | Container-level security context override for the Envoy container. When empty, the chart keeps its secure default (runAsNonRoot, runAsUser 101, readOnlyRootFilesystem, no privilege escalation, all capabilities dropped). Override only when you understand the security trade-off. |
| gateway.podTemplate.serviceAccountName | string | `""` | ServiceAccount used by gateway pods. When empty, the namespace `default` ServiceAccount is used (the chart does not create one). |
| gateway.podTemplate.sidecars | list | `[]` | Extra sidecar containers appended to the gateway pod's `containers`. |
| gateway.podTemplate.tolerations | list | `[]` | Tolerations for gateway pod scheduling. |
| gateway.podTemplate.topologySpreadConstraints | list | `[]` | Topology spread constraints. With 2 default replicas, set this to force zone or node spread so a single failure cannot take down both gateway pods at once. |
| gateway.podTemplate.volumeMounts | list | `[]` | Extra volume mounts added to the Envoy container, merged with the chart-managed mounts. |
| gateway.podTemplate.volumes | list | `[]` | Extra volumes added to the gateway pod, merged with the chart-managed volumes. Mount them on the Envoy container via `volumeMounts` below. |
| gateway.replicas | int | `2` | Number of gateway replicas. |
| gateway.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits for the Envoy container. |
| gateway.service | object | {} | Gateway Service configuration. |
| gateway.service.port | int | `80` | External service port proxied to `containerPort`. |
| gateway.service.type | string | `"ClusterIP"` | Service type. One of `ClusterIP`, `LoadBalancer`, or `NodePort`. |
| imagePullSecrets | list | `[]` | Registry credentials. Must be a pre-created docker-registry Secret in the deployment namespace. Leave empty if nodes have ambient registry access (e.g. node IAM role). |
| metadata | object | {} | Metadata service configuration. |
| metadata.deployment | object | {} | Deployment-level settings for the metadata service. |
| metadata.deployment.terminationGracePeriodSeconds | int | `30` | Termination grace period in seconds. |
| metadata.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| metadata.image.repository | string | `"ghcr.io/firebolt-db/metadata"` | Container repository for the metadata service image. |
| metadata.image.tag | string | `""` | Metadata service image tag. Defaults to `Chart.appVersion` (kept in lockstep with the engine) when empty. Override explicitly only when the metadata service must run a version other than the engine. |
| metadata.podTemplate | object | {} | Pod template overrides for the metadata service. Only the keys listed below are read by the chart; arbitrary [PodSpec](https://pkg.go.dev/k8s.io/api/core/v1#PodSpec) fields supplied here are silently ignored. Overrides are additive and do not lower the chart's security floor: the metadata pod keeps its non-root pod- and container-level defaults (drop-ALL capabilities) unless you explicitly replace them via `podSecurityContext` / `securityContext` below. |
| metadata.podTemplate.affinity | object | `{}` | Affinity rules for metadata pod scheduling. |
| metadata.podTemplate.envFrom | list | `[]` | `envFrom` sources (ConfigMap/Secret) for the metadata container. |
| metadata.podTemplate.extraEnv | list | `[]` | Extra environment variables appended to the metadata container. |
| metadata.podTemplate.extraPodLabels | object | `{}` | Extra labels applied to the metadata pod template. |
| metadata.podTemplate.imagePullSecrets | list | `[]` | Per-component image pull secrets, concatenated with the top-level `imagePullSecrets`. |
| metadata.podTemplate.initContainers | list | `[]` | Init containers injected into the metadata pod. |
| metadata.podTemplate.lifecycle | object | {} | Lifecycle hooks for the metadata container. When empty, no lifecycle hooks are set. |
| metadata.podTemplate.nodeSelector | object | `{}` | Node selector for metadata pod scheduling. |
| metadata.podTemplate.podAnnotations | object | `{}` | Extra annotations applied to the metadata pod template. Merged with the chart-managed checksum annotations. |
| metadata.podTemplate.podSecurityContext | object | {} | Pod-level security context override for the metadata pod. When empty, the chart keeps its secure default (runAsNonRoot, runAsUser/Group 1111, RuntimeDefault seccomp profile). Override only when you understand the security trade-off. |
| metadata.podTemplate.priorityClassName | string | `""` | Pod priority class. Reference a `PriorityClass` to let the metadata service preempt lower-priority workloads under resource pressure. |
| metadata.podTemplate.securityContext | object | {} | Container-level security context override for the metadata container. When empty, the chart keeps its secure default (runAsNonRoot, runAsUser 1111, readOnlyRootFilesystem, no privilege escalation, all capabilities dropped). Override only when you understand the security trade-off. |
| metadata.podTemplate.serviceAccountName | string | `""` | ServiceAccount used by metadata pods. When empty, the namespace `default` ServiceAccount is used (the chart does not create one). |
| metadata.podTemplate.sidecars | list | `[]` | Extra sidecar containers appended to the metadata pod's `containers`. |
| metadata.podTemplate.tolerations | list | `[]` | Tolerations for metadata pod scheduling. |
| metadata.podTemplate.topologySpreadConstraints | list | `[]` | Topology spread constraints for metadata pod scheduling. |
| metadata.podTemplate.volumeMounts | list | `[]` | Extra volume mounts added to the metadata container, merged with the chart-managed mounts. |
| metadata.podTemplate.volumes | list | `[]` | Extra volumes added to the metadata pod, merged with the chart-managed volumes. Mount them on the metadata container via `volumeMounts` below. |
| metadata.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` | Resource requests and limits for the metadata service container. The metadata service is a lightweight gRPC service; increase memory if you run many engines. |
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
| postgresql.image | string | `"postgres:16-alpine@sha256:16bc17c64a573ef34162af9298258d1aec548232985b33ed7b1eac33ba35c229"` | PostgreSQL image used for the bundled StatefulSet. Pinned to an immutable digest so a registry-side tag override cannot silently change what runs in production. The `postgres:16-alpine` tag prefix is retained for readability only; resolution happens on the digest. Bump both the tag and the digest together when upgrading. |
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
| tls | object | {} | TLS configuration for the Envoy gateway's client-facing listener and the engine's query listener. Each of `gateway` / `engine` is provisioned by exactly one of `existingSecret` (a `kubernetes.io/tls` Secret) or `certManager` (a chart-rendered cert-manager `Certificate`); setting both or neither on an enabled block fails the render. |
| tls.engine | object | {} | TLS on the engine's query listener (port 3473) and, correspondingly, the gateway's upstream connection to engines (including the active engine health check, which runs over the same connection). |
| tls.engine.certManager | object | {} | cert-manager `Certificate` request. DNS names are derived automatically from the engine's per-node and headless-service FQDNs. Requires cert-manager and its CRDs installed in-cluster. |
| tls.engine.certManager.algorithm | string | `"RSA"` | Private key algorithm. One of `RSA` or `ECDSA`. |
| tls.engine.certManager.issuerRef | object | {} | cert-manager issuer reference. |
| tls.engine.certManager.issuerRef.kind | string | `"ClusterIssuer"` | Issuer kind. One of `Issuer` or `ClusterIssuer`. |
| tls.engine.certManager.issuerRef.name | string | `""` | Issuer name. |
| tls.engine.certManager.size | int | `2048` | Private key size in bits. |
| tls.engine.enabled | bool | `false` | Enable TLS on the engine query listener. |
| tls.engine.existingSecret | object | {} | Existing `kubernetes.io/tls` Secret. Requires all three keys: `tls.crt` / `tls.key`, plus `ca.crt` with the issuing CA — both the engine's own self-health-check and the gateway need `ca.crt` on its own to validate the chain. For a genuinely self-signed leaf with no separate CA, set `ca.crt` to a copy of `tls.crt`. |
| tls.engine.existingSecret.secretRef | string | `""` | Secret name. |
| tls.gateway | object | {} | TLS termination at the Envoy gateway (client → gateway). |
| tls.gateway.certManager | object | {} | cert-manager `Certificate` request. Requires cert-manager and its CRDs installed in-cluster. |
| tls.gateway.certManager.algorithm | string | `"RSA"` | Private key algorithm. One of `RSA` or `ECDSA`. |
| tls.gateway.certManager.dnsNames | list | `[]` | DNS names for the certificate. The chart cannot infer the externally-visible gateway hostname — set this explicitly (e.g. the LoadBalancer hostname or ingress DNS name). |
| tls.gateway.certManager.issuerRef | object | {} | cert-manager issuer reference. |
| tls.gateway.certManager.issuerRef.kind | string | `"ClusterIssuer"` | Issuer kind. One of `Issuer` or `ClusterIssuer`. |
| tls.gateway.certManager.issuerRef.name | string | `""` | Issuer name. |
| tls.gateway.certManager.size | int | `2048` | Private key size in bits. |
| tls.gateway.enabled | bool | `false` | Enable TLS on the gateway's client-facing listener. |
| tls.gateway.existingSecret | object | {} | Existing `kubernetes.io/tls` Secret (`tls.crt` / `tls.key`). |
| tls.gateway.existingSecret.secretRef | string | `""` | Secret name. |
| utilitiesImage | string | `"debian:stable-slim@sha256:5012d0517aa0075a7150a45aae67586641e898913b7af3b08228108565b5f90c"` | Image used for utility init/sidecar containers (e.g. the memlock-setup sidecar). Pinned to an immutable digest so a registry-side tag override cannot silently change what runs in production. Bump the digest together with the tag when upgrading. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
