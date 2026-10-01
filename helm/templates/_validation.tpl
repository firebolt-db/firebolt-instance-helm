{{/* Render-time checks for combinations that JSON Schema cannot express. */}}
{{- define "fbinstance.validatePodExtras" -}}
{{- $context := .context -}}
{{- $seen := dict -}}
{{- range .env -}}
  {{- if or (has .name $.reservedEnv) (hasKey $seen .name) -}}
    {{- fail (printf "%s: duplicate or chart-owned environment variable %s" $context .name) -}}
  {{- end -}}
  {{- $_ := set $seen .name true -}}
{{- end -}}
{{- $seen = dict -}}
{{- range .volumes -}}
  {{- if or (has .name $.reservedVolumes) (hasPrefix "auth-signing-" .name) (hasKey $seen .name) -}}
    {{- fail (printf "%s: duplicate or chart-owned volume %s" $context .name) -}}
  {{- end -}}
  {{- $_ := set $seen .name true -}}
{{- end -}}
{{- $mountPaths := dict -}}
{{- range .mounts -}}
  {{- $path := clean .mountPath -}}
  {{- if hasKey $mountPaths $path -}}
    {{- fail (printf "%s: duplicate volume mount path: %s" $context $path) -}}
  {{- end -}}
  {{- $_ := set $mountPaths $path true -}}
  {{- $collision := or (has .name $.reservedVolumes) (hasPrefix "auth-signing-" .name) -}}
  {{- range $reserved := $.reservedPaths -}}
    {{- $reserved = clean $reserved -}}
    {{- if or (eq $path $reserved) (and (ne $reserved "/") (or (hasPrefix (printf "%s/" $reserved) $path) (hasPrefix (printf "%s/" $path) $reserved))) -}}
      {{- $collision = true -}}
    {{- end -}}
  {{- end -}}
  {{- if $collision -}}
    {{- fail (printf "%s: volume mount collides with a chart-owned mount: %s" $context .mountPath) -}}
  {{- end -}}
{{- end -}}
{{- range $key, $_ := .annotations -}}
  {{- if or (hasPrefix "checksum/" $key) (hasPrefix "firebolt.io/" $key) -}}
    {{- fail (printf "%s: annotation %s is reserved for chart rollout tracking" $context $key) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "fbinstance.validate" -}}
{{- $root := . -}}
{{- $name := include "fbinstance.fullname" . -}}
{{- range $suffix := list "-metadata-service" "-metadata-pg" "-gateway" -}}
  {{- if gt (len (printf "%s%s" $name $suffix)) 63 -}}
    {{- fail "release name is too long for the chart's generated Service names (maximum 63 characters)" -}}
  {{- end -}}
{{- end -}}
{{- $seen := dict -}}
{{- range .Values.engines -}}
  {{- if hasKey $seen .name -}}{{- fail (printf "duplicate engine name: %s" .name) -}}{{- end -}}
  {{- $_ := set $seen .name true -}}
  {{- if or (gt (len (printf "%s-engine-%s-node-%d-0" $name .name (int (sub .replicas 1)))) 63) (gt (len (printf "%s-engine-%s-ready" $name .name)) 63) -}}
    {{- fail (printf "engine %s: generated pod or Service name exceeds 63 characters; shorten the release or engine name" .name) -}}
  {{- end -}}
  {{- include "fbinstance.validatePodExtras" (dict "context" (printf "engine %s" .name) "env" .extraEnv "volumes" .customVolumes "mounts" .customVolumeMounts "annotations" .podAnnotations "reservedEnv" (list "FIREBOLT_CORE_NODE" "POD_UID" "NODES_COUNT" "FB_AWS_EC2_METADATA_CLIENT_ENABLED" "FIREBOLT_CORE_MODE") "reservedVolumes" (list "data" "runtime" "engine-config" "auth-admin" "engine-tls-raw" "engine-tls-chain" "nginx-writable-dir") "reservedPaths" (list "/" "/var/lib/firebolt" "/var/lib/firebolt/config.yaml" "/run/firebolt" "/secrets" "/etc/firebolt/tls/engine")) -}}
{{- end -}}
{{- include "fbinstance.validatePodExtras" (dict "context" "engineSpec" "env" .Values.engineSpec.extraEnv "volumes" .Values.engineSpec.customVolumes "mounts" .Values.engineSpec.customVolumeMounts "annotations" .Values.engineSpec.podAnnotations "reservedEnv" (list "FIREBOLT_CORE_NODE" "POD_UID" "NODES_COUNT" "FB_AWS_EC2_METADATA_CLIENT_ENABLED" "FIREBOLT_CORE_MODE") "reservedVolumes" (list "data" "runtime" "engine-config" "auth-admin" "engine-tls-raw" "engine-tls-chain" "nginx-writable-dir") "reservedPaths" (list "/" "/var/lib/firebolt" "/var/lib/firebolt/config.yaml" "/run/firebolt" "/secrets" "/etc/firebolt/tls/engine")) -}}
{{- range $component := list "metadata" "gateway" -}}
  {{- $p := index $root.Values $component "podTemplate" -}}
  {{- include "fbinstance.validatePodExtras" (dict "context" $component "env" $p.extraEnv "volumes" $p.volumes "mounts" $p.volumeMounts "annotations" $p.podAnnotations "reservedEnv" (list "POSTGRES_USERNAME_FILE" "POSTGRES_PASSWORD_FILE" "POSTGRES_SSLMODE" "POSTGRES_SSLROOTCERT") "reservedVolumes" (list "config" "postgres-creds" "postgres-ca" "tmp" "gateway-config" "gateway-tls" "engine-ca") "reservedPaths" (list "/" "/configs" $root.Values.postgresql.credentials.mountPath "/etc/envoy" "/tmp")) -}}
{{- end -}}
{{- $seen = dict -}}
{{- range .Values.auth.signingKeys -}}
  {{- if hasKey $seen .id -}}{{- fail (printf "duplicate signing key id: %s" .id) -}}{{- end -}}
  {{- $_ := set $seen .id true -}}
{{- end -}}
{{- if and (not .Values.postgresql.local_enabled) (not .Values.postgresql.host) -}}
  {{- fail "postgresql.host is required when postgresql.local_enabled is false" -}}
{{- end -}}
{{/* Helm client-side rendering has no live state; deployment tooling must enforce identity there. */}}
{{- if .Release.IsUpgrade -}}
  {{- $existing := lookup "v1" "ConfigMap" .Release.Namespace (printf "%s-metadata-service" $name) -}}
  {{- if and $existing $existing.data (hasKey $existing.data "config.yaml") -}}
    {{- $previous := index $existing.data "config.yaml" | fromYaml -}}
    {{- $oldID := dig "pensieve_lite" "default_account_id" "" $previous -}}
    {{- if and $oldID (ne $oldID .Values.customEngineConfig.instance.id) -}}
      {{- fail "customEngineConfig.instance.id is installation identity and cannot change on upgrade" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
