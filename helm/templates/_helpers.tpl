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
Engine ServiceAccount name. Empty `engineSpec.serviceAccount` ->
`<fullname>-engine` (chart-managed; the SA template renders it).
Non-empty `engineSpec.serviceAccount` -> verbatim, and the chart does
not render a SA manifest (bring your own — IRSA / Pod Identity flow).
Both the SA template and the engine StatefulSet podSpec MUST resolve
the name through this helper so a single value drives both sides.
*/}}
{{- define "fbinstance.engineServiceAccountName" -}}
{{- default (printf "%s-engine" (include "fbinstance.fullname" .)) .Values.engineSpec.serviceAccount -}}
{{- end -}}

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
and `instance` (e.g. `logging:`), and keys nested under `instance:`
merge into the inner instance block (e.g. `instance.id`, which the
engine internally propagates to account_id, account_name,
organization_id, and organization_name; or `instance.auth.oidc` /
`instance.auth.local.signing_algorithm` / `instance.auth.jwt`,
deep-merged alongside the auth.* value block below).

Chart-authoritative paths are silently stripped from the user input
before the merge: `schema_version`, `engine.id`, `engine.nodes`,
`engine.termination_grace_period`, `instance.type`,
`instance.multi_engine`, and — only when `tls.engine.enabled` — the
`endpoints.http.listeners` this helper renders for the query
listener's TLS. The same customEngineConfig therefore stays portable
across chart versions.

When `auth.enabled` is true, `instance.auth.{enabled,admin,
local.signing_keys}` are built from `auth.admin` / `auth.signingKeys`
using chart-owned secret mount paths (see engine-statefulset.yaml for
the matching volumes); rendering nothing under `instance.auth`
otherwise, since the engine refuses to start if `admin` / `oidc` /
`preferred_authorization_server` are present while auth is disabled.
`auth.enabled` with an empty `auth.signingKeys` fails the render — an
engine with no explicit signing key falls back to a per-pod dev key
that differs across nodes and breaks cross-node token validation.

When `tls.engine.enabled` is true, `endpoints.http.listeners` is set
to a single TLS-terminated TCP listener on the query port (3473),
using the combined-chain file an init container builds from the
mounted TLS secret (see engine-statefulset.yaml) — the engine's own
internal health-check dials this listener over HTTPS and needs the
issuing CA reachable from the same file it serves.

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

{{- $instanceCanonical := dict "type" "multi_engine" "multi_engine" (dict "metadata_endpoint" $metadataEndpoint) -}}
{{- if $root.Values.auth.enabled -}}
{{-   if not $root.Values.auth.admin.password.existingSecret.secretRef -}}
{{-     fail "auth.enabled is true but auth.admin.password.existingSecret.secretRef is empty — enabling auth requires an existing Secret with the admin password" -}}
{{-   end -}}
{{-   if not $root.Values.auth.signingKeys -}}
{{-     fail "auth.enabled is true but auth.signingKeys is empty — an engine with no explicit signing key falls back to a per-pod dev key that differs across nodes and breaks token validation in a multi-node engine" -}}
{{-   end -}}
{{-   $signingKeys := list -}}
{{-   range $ki, $key := $root.Values.auth.signingKeys -}}
{{-     if not $key.id -}}
{{-       fail (printf "auth.signingKeys[%d].id is empty — every signing key needs a non-empty id, published as the JWT kid header" $ki) -}}
{{-     end -}}
{{-     $signingKeys = append $signingKeys (dict "id" $key.id "private_key_path" (printf "/secrets/auth/signing-%d/tls.key" $ki)) -}}
{{-   end -}}
{{-   $_ := set $instanceCanonical "auth" (dict
        "enabled" true
        "admin" (dict "name" $root.Values.auth.admin.name "password_file" "/secrets/auth/admin/password")
        "local" (dict "signing_keys" $signingKeys)
      ) -}}
{{- end -}}

{{- $canonical := dict
      "schema_version" "1.0"
      "engine" (dict "id" $engine.name "nodes" $nodes "termination_grace_period" (printf "%ds" $shutdownWait))
      "instance" $instanceCanonical
      "logging" (dict "format" "json")
-}}
{{- if $root.Values.tls.engine.enabled -}}
{{-   $_ := set $canonical "endpoints" (dict "http" (dict "listeners" (list (dict
        "type" "tcp"
        "port" 3473
        "tls" (dict
          "certificate_file" "/etc/firebolt/tls/engine/fullchain.pem"
          "private_key_file" "/secrets/tls/engine-raw/tls.key"
        )
      )))) -}}
{{/*
  endpoints.http.listeners is only chart-authoritative while we're actually
  rendering it (tls.engine.enabled); leave it fully user-controlled via
  customEngineConfig otherwise (e.g. to add a unix-socket listener with TLS
  off).
*/}}
{{-   if hasKey $user "endpoints" -}}
{{-     if kindIs "map" $user.endpoints -}}
{{-       if and (hasKey $user.endpoints "http") (kindIs "map" $user.endpoints.http) -}}
{{-         $_ := unset $user.endpoints.http "listeners" -}}
{{-       else if hasKey $user.endpoints "http" -}}
{{-         $_ := unset $user.endpoints "http" -}}
{{-       end -}}
{{-     else -}}
{{-       $_ := unset $user "endpoints" -}}
{{-     end -}}
{{-   end -}}
{{- end -}}

{{- $merged := mergeOverwrite $canonical $user -}}
{{ $merged | toYaml }}
{{- end -}}

{{/*
Resolves a "secret source" object — {existingSecret: {secretRef}, certManager: {...}} —
to the name of the Kubernetes Secret that should be mounted. Exactly one of
existingSecret.secretRef or certManager.issuerRef.name must be set (the presence of a
non-empty issuerRef.name is what distinguishes "certManager configured" from "certManager
left at its structural defaults", since the value tree always carries the certManager map).
Fails the render otherwise, naming the offending value path.

Usage: {{ include "fbinstance.secretSourceName" (dict "source" <secretSourceValue> "certManagerSecretName" <name> "context" "<value path, for error messages>") }}
*/}}
{{- define "fbinstance.secretSourceName" -}}
{{- $source := .source -}}
{{- $hasExisting := and $source.existingSecret (ne ($source.existingSecret.secretRef | default "") "") -}}
{{- $hasCertManager := and $source.certManager $source.certManager.issuerRef (ne ($source.certManager.issuerRef.name | default "") "") -}}
{{- if and $hasExisting $hasCertManager -}}
{{- fail (printf "%s: set exactly one of existingSecret.secretRef or certManager.issuerRef.name, not both" .context) -}}
{{- else if $hasExisting -}}
{{- $source.existingSecret.secretRef -}}
{{- else if $hasCertManager -}}
{{- .certManagerSecretName -}}
{{- else -}}
{{- fail (printf "%s: set one of existingSecret.secretRef or certManager.issuerRef.name" .context) -}}
{{- end -}}
{{- end -}}

{{/*
True (non-empty string "true") when a secret-source object's certManager block is the one
in effect, i.e. the chart should render a cert-manager Certificate for it. Mirrors the
certManager branch of fbinstance.secretSourceName's resolution but never fails — safe to use
as a template guard ({{- if include "fbinstance.usesCertManager" (dict "source" ...) }}).
The corresponding fbinstance.secretSourceName call at the mount site still enforces the
exactly-one-of validation.

Usage: {{ include "fbinstance.usesCertManager" (dict "source" <secretSourceValue>) }}
*/}}
{{- define "fbinstance.usesCertManager" -}}
{{- $source := .source -}}
{{- $hasExisting := and $source.existingSecret (ne ($source.existingSecret.secretRef | default "") "") -}}
{{- $hasCertManager := and $source.certManager $source.certManager.issuerRef (ne ($source.certManager.issuerRef.name | default "") "") -}}
{{- if and $hasCertManager (not $hasExisting) -}}true{{- end -}}
{{- end -}}

{{/*
DNS names for the shared engine TLS certificate (one Secret/Certificate mounted by every
engine pod across every engine in .Values.engines). Includes every node's per-node FQDN,
each engine's headless-service FQDN, and "localhost".

MUST track the exact node-FQDN format fbinstance.engineConfig builds (the `$fqdn` in its
`engine.nodes` list): that format is the hostname the engine's own internal
FireboltCoreHealthChecker dials once TLS is enabled (it uses the node's configured hostname,
not localhost, for both the connection and SNI/cert verification — see
FireboltCoreHealthChecker.cpp). A mismatch here leaves every engine node permanently
NotReady, not just cosmetically wrong.

Usage: {{ include "fbinstance.engineTlsDnsNames" . }}
*/}}
{{- define "fbinstance.engineTlsDnsNames" -}}
{{- $root := . -}}
{{- $ns := $root.Release.Namespace -}}
{{- $names := list "localhost" -}}
{{- range $engine := $root.Values.engines -}}
{{-   $baseName := printf "%s-engine-%s" (include "fbinstance.fullname" $root) $engine.name -}}
{{-   $svcName := printf "%s-hl" $baseName -}}
{{-   $names = append $names (printf "%s.%s.svc%s" $svcName $ns $root.Values.engineSpec.nodeHostSuffix) -}}
{{-   range $i := until (int $engine.replicas) -}}
{{-     $names = append $names (printf "%s-node-%d-0.%s.%s.svc%s" $baseName $i $svcName $ns $root.Values.engineSpec.nodeHostSuffix) -}}
{{-   end -}}
{{- end -}}
{{- toYaml $names -}}
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
