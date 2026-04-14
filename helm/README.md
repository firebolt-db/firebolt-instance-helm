# firebolt-instance

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Firebolt Instance on Kubernetes — gateway, metadata, auth, and engines

**Homepage:** <https://github.com/firebolt-db/firebolt-instance-helm>

## Source Code

* <https://github.com/firebolt-db/firebolt-instance-helm>

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://charts.bitnami.com/bitnami | postgresql | ~18.0.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| auth | object | `{"local":{"credentialsSecretRef":""},"mode":"none","oidc":{"claimMappings":{"username":"email"},"clientID":"","issuerURL":""}}` | ------------------------------------------------------------------------- |
| createNamespace | bool | `true` |  |
| customNodeConfig | object | `{}` |  |
| defaultStorage | object | `{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"100Gi"}}}` | ------------------------------------------------------------------------- storageClassName is intentionally absent — the cluster default storage class is used. Override here or per-engine if your cluster requires a specific class (e.g. storageClassName: gp3). |
| engines | list | `[{"affinity":{},"name":"default","nodeSelector":{},"podAnnotations":{},"priorityClassName":"","replicas":1,"resources":{"limits":{"cpu":"8","memory":"64Gi"},"requests":{"cpu":"4","memory":"32Gi"}},"storage":{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"100Gi"}}},"tolerations":[]}]` | ------------------------------------------------------------------------- Each entry produces one StatefulSet + headless Service + ClusterIP Service + ConfigMap. Per-engine values override the shared pod defaults above. |
| fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| gateway | object | `{"auth":{"directAccessSecret":""},"enabled":false,"image":{"repository":"000000000000.dkr.ecr.us-east-1.amazonaws.com/core-gateway","tag":""},"organization":{"accountId":"","name":""},"podTemplate":{},"replicas":1,"resources":{"limits":{"memory":"1Gi"},"requests":{"cpu":"500m","memory":"512Mi"}},"service":{"port":3473,"type":"ClusterIP"}}` | ------------------------------------------------------------------------- |
| image.pullPolicy | string | `"Always"` |  |
| image.repository | string | `"000000000000.dkr.ecr.us-east-1.amazonaws.com/firebolt-core"` |  |
| imagePullSecrets | list | `[]` |  |
| memlockSetup | bool | `true` |  |
| metadata | object | `{"deployment":{"securityContext":{},"terminationGracePeriodSeconds":30},"image":{"repository":"000000000000.dkr.ecr.us-east-1.amazonaws.com/dedicated-pensieve","tag":""},"podTemplate":{},"postgresql":{"connect_timeout_sec":5,"credentials":{"existingSecret":"","mountPath":"/secrets/postgres","password":"","username":""},"database":"","host":"","keepalive":{"count":5,"enabled":1,"idle_sec":120,"interval_sec":30},"port":5432,"schema":"public"},"resources":{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}},"server":{"host":"0.0.0.0","log_level":"information","port":7000,"threads":0}}` | ------------------------------------------------------------------------- |
| nodeSelector | object | `{}` |  |
| nonRoot | bool | `true` | ------------------------------------------------------------------------- |
| podMonitor | bool | `false` |  |
| postgresql | object | `{"auth":{"database":"firebolt_metadata","password":"","username":"firebolt"},"enabled":true,"primary":{"persistence":{"size":"10Gi"}}}` | ------------------------------------------------------------------------- Set enabled: false and configure metadata.postgresql for an external database. |
| securityContextCapabilities.drop[0] | string | `"ALL"` |  |
| serviceAccount | string | `"default"` |  |
| terminationGracePeriodSeconds | int | `5` |  |
| tolerations | list | `[]` |  |
| utilitiesImage | string | `"debian:stable-slim"` |  |
| version | string | `""` |  |

