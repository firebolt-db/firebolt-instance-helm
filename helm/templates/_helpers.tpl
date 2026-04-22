{{/*
Expand the name of the chart.
*/}}
{{- define "fbinstance.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully-qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
The release name is used as-is — the chart name is intentionally excluded to avoid
prefix duplication when the release name already contains "firebolt".
*/}}
{{- define "fbinstance.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fbinstance.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "fbinstance.labels" -}}
{{ include "fbinstance.selectorLabels" . }}
helm.sh/chart: {{ include "fbinstance.chart" . }}
{{- with (default .Chart.AppVersion .Values.engineSpec.image.tag) }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.extraLabels }}
{{ toYaml .Values.extraLabels }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "fbinstance.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fbinstance.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Pod template labels — stable subset of fbinstance.labels, intentionally excludes
app.kubernetes.io/version so that a version bump on an unrelated component does
not mutate the pod template and trigger an unwanted rollout.
*/}}
{{- define "fbinstance.podLabels" -}}
{{ include "fbinstance.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common engine ports
*/}}
{{- define "fbinstance.enginePorts" -}}
- name: http-query
  port: 3473
  protocol: TCP
- name: health
  port: 8122
  protocol: TCP
- name: execp
  port: 5678
  protocol: TCP
- name: datacp
  port: 16000
  protocol: TCP
- name: storage-manager
  port: 1717
  protocol: TCP
- name: storage-agent
  port: 3434
  protocol: TCP
- name: metadata
  port: 6500
  protocol: TCP
- name: metrics
  port: 9090
  protocol: TCP
{{- if .Values.engineSpec.uiSidecar }}
- name: web-ui
  port: 9100
  protocol: TCP
{{- end }}
{{- end }}

{{/*
Engine config JSON helper.
Produces a JSON object with nodes (Pod FQDNs) and the metadata endpoint.
Usage: {{ include "fbinstance.engineConfig" (dict "root" $ "engine" $engine) }}
*/}}
{{- define "fbinstance.engineConfig" -}}
{{- $root := .root -}}
{{- $engine := .engine -}}
{{- $baseName := printf "%s-engine-%s" (include "fbinstance.fullname" $root) $engine.name -}}
{{- $svcName := printf "%s-hl" $baseName -}}
{{- $ns := $root.Release.Namespace -}}
{{- $pensieveSvc := printf "%s-metadata-service" (include "fbinstance.fullname" $root) -}}
{{- $nodes := list -}}
{{- range $i := until (int $engine.replicas) -}}
{{-   $fqdn := printf "%s-node-%d-0.%s.%s.svc%s" $baseName $i $svcName $ns $root.Values.engineSpec.nodeHostSuffix -}}
{{-   $nodes = append $nodes (dict "host" $fqdn) -}}
{{- end -}}
{{- $innerConfig := dict "multi_engine_endpoint" (printf "%s.%s.svc.cluster.local:%d" $pensieveSvc $ns (int $root.Values.metadata.server.port)) "multi_engine_mode_enabled" true "engine_id" $engine.name "engine_name" $engine.name -}}
{{- if $root.Values.customNodeConfig -}}
{{-   $innerConfig = merge $innerConfig $root.Values.customNodeConfig -}}
{{- end -}}
{{- $config := dict "config" $innerConfig "nodes" $nodes -}}
{{ $config | toPrettyJson }}
{{- end -}}

{{/*
Auth config JSON helper.
Produces a JSON object based on auth.mode.
*/}}
{{- define "fbinstance.authConfig" -}}
{{- if eq .Values.auth.mode "none" -}}
{"mode": "none"}
{{- else if eq .Values.auth.mode "local" -}}
{"mode": "local", "credentialsSecretRef": {{ .Values.auth.local.credentialsSecretRef | quote }}}
{{- else if eq .Values.auth.mode "sso" -}}
{
  "mode": "sso",
  "oidc": {
    "issuerURL": {{ .Values.auth.oidc.issuerURL | quote }},
    "clientID": {{ .Values.auth.oidc.clientID | quote }},
    "claimMappings": {{ .Values.auth.oidc.claimMappings | toJson }}
  }
}
{{- else }}
{{- fail (printf "auth.mode must be one of: none, local, sso. Got: %s" .Values.auth.mode) }}
{{- end }}
{{- end }}

{{/*
Memlock setup sidecar script — loaded from files/memlock-setup.sh
*/}}
{{- define "fbinstance.memlockSetupScript" -}}
{{ .Files.Get "files/memlock-setup.sh" }}
{{- end }}

{{/*
Shared colored log/pass/fail helpers for helm test pods.
Usage inside a test script:
    set -e
    {{`{{- include "fbinstance.testShellHelpers" . | nindent 10 }}`}}
    log  "section header"
    pass "success message"
    fail "failure reason (exits 1)"
*/}}
{{- define "fbinstance.testShellHelpers" -}}
log()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }
{{- end }}
