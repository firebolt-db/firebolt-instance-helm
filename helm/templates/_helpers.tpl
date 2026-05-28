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
Engine Service ports. Only externally-meaningful endpoints are declared:
http-query (SQL), health (probe / Envoy active health check), metrics
(Prometheus scrape), and optionally web-ui (sidecar). The intra-engine
peer ports — aragog (5678), shufflepuff (16000), storage-manager (1717),
storage-agent (3434) — are intentionally omitted: they're carried over
the headless service's pod-IP DNS records, so no Service port entry is
needed for engine nodes to reach each other.
*/}}
{{- define "fbinstance.enginePorts" -}}
- name: http-query
  port: 3473
  protocol: TCP
- name: health
  port: 8122
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
Engine config YAML helper.
Produces the rendered engine config.yaml document following the
Firebolt Core configuration schema (`schema_version: "1.0"`). The
canonical document has shape:

    schema_version: "1.0"
    engine:
      id: <engine name>
      nodes:
        - host: <fqdn>
      termination_grace_period: <pod TGPS minus 5s, in seconds>
    instance:
      type: multi_engine
      multi_engine:
        metadata_endpoint: <pensieve gRPC endpoint>
    logging:
      format: json

.Values.customEngineConfig is deep-merged on top of the canonical
document at the root: keys at the top become siblings of `engine`
and `instance` (e.g. `auth:`, `logging:`), and keys nested under
`instance:` merge into the inner instance block (e.g. `instance.id`,
which the engine internally propagates to account_id, account_name,
organization_id, and organization_name).

Chart-authoritative paths are silently stripped from the user input
before the merge: `schema_version`, `engine.id`, `engine.nodes`,
`engine.termination_grace_period`, `instance.type`,
`instance.multi_engine`. The same customEngineConfig therefore stays
portable across chart versions.

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
{{- $metadataEndpoint := printf "%s.%s.svc.cluster.local:%d" $pensieveSvc $ns (int $root.Values.metadata.server.port) -}}
{{/*
  Engine's own post-SIGTERM in-flight-query budget: the pod's
  terminationGracePeriodSeconds minus a 5s margin so the engine exits before
  the kubelet escalates to SIGKILL, floored at 1s. A single clamp keeps the
  budget monotonic non-decreasing in the grace period.
*/}}
{{- $gracePeriod := int $root.Values.engineSpec.terminationGracePeriodSeconds -}}
{{- $shutdownWait := sub $gracePeriod 5 -}}
{{- if lt $shutdownWait 1 -}}{{- $shutdownWait = 1 -}}{{- end -}}
{{- $canonical := dict
      "schema_version" "1.0"
      "engine" (dict "id" $engine.name "nodes" $nodes "termination_grace_period" (printf "%ds" $shutdownWait))
      "instance" (dict "type" "multi_engine" "multi_engine" (dict "metadata_endpoint" $metadataEndpoint))
      "logging" (dict "format" "json")
-}}
{{- $user := deepCopy (default (dict) $root.Values.customEngineConfig) -}}
{{- $_ := unset $user "schema_version" -}}
{{/*
  When user.engine / user.instance is not a map (string, number, list…) drop
  it entirely: mergeOverwrite would otherwise replace the chart-built block
  wholesale with the user's scalar, losing every authoritative key.
*/}}
{{- if hasKey $user "engine" -}}
{{-   if kindIs "map" $user.engine -}}
{{-     $_ := unset $user.engine "id" -}}
{{-     $_ := unset $user.engine "nodes" -}}
{{-     $_ := unset $user.engine "termination_grace_period" -}}
{{-   else -}}
{{-     $_ := unset $user "engine" -}}
{{-   end -}}
{{- end -}}
{{- if hasKey $user "instance" -}}
{{-   if kindIs "map" $user.instance -}}
{{-     $_ := unset $user.instance "type" -}}
{{-     $_ := unset $user.instance "multi_engine" -}}
{{-   else -}}
{{-     $_ := unset $user "instance" -}}
{{-   end -}}
{{- end -}}
{{- $merged := mergeOverwrite $canonical $user -}}
{{ $merged | toYaml }}
{{- end -}}

{{/*
XML element-text escape for user-controlled strings interpolated into the
rendered metadata config.xml. Replaces the three element-content
metacharacters; the `&` substitution MUST run first so its entity
reference isn't re-escaped. Defense-in-depth alongside the
values.schema.json patterns.
*/}}
{{- define "fbinstance.xmlEscape" -}}
{{- . | replace "&" "&amp;" | replace "<" "&lt;" | replace ">" "&gt;" -}}
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
