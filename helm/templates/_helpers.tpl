{{/*
Expand the name of the chart.
*/}}
{{- define "fbinstance.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully-qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fbinstance.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
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
{{- $baseName := printf "%s-%s" (include "fbinstance.fullname" $root) $engine.name -}}
{{- $svcName := printf "%s-hl" $baseName -}}
{{- $ns := $root.Release.Namespace -}}
{{- $pensieveSvc := printf "%s-pensieve-dedicated" (include "fbinstance.fullname" $root) -}}
{{- $nodes := list -}}
{{- range $i := until (int $engine.replicas) -}}
{{-   $fqdn := printf "%s-node-%d-0.%s.%s.svc%s" $baseName $i $svcName $ns $root.Values.engineSpec.nodeHostSuffix -}}
{{-   $nodes = append $nodes (dict "host" $fqdn) -}}
{{- end -}}
{{- $config := dict "nodes" $nodes "multi_engine_endpoint" (printf "%s.%s.svc.cluster.local:%d" $pensieveSvc $ns (int $root.Values.metadata.server.port)) -}}
{{- if $root.Values.customNodeConfig -}}
{{-   $config = merge $config $root.Values.customNodeConfig -}}
{{- end -}}
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
