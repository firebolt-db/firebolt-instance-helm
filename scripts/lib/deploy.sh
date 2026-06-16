#!/usr/bin/env bash
# Shared helpers for deploying the firebolt-instance chart to kind and proving
# it serves queries, plus the agent JSON-output plumbing.
#
# Sourced by both the CI PR gate (scripts/ci/helm-test.sh) and the agent
# entrypoints (scripts/agent/{up,verify,down}.sh) — that shared use is why this
# lives in scripts/lib/ rather than under scripts/ci/. The functions deploy the
# chart against floci, wait for workloads to roll out, and prove a query reaches
# an engine through the Envoy gateway, mirroring docs/quickstart.mdx. They dump
# namespace state on failure: a CI kind cluster is destroyed when the job ends,
# so anything not printed here is lost.

set -euo pipefail

# Dump pods, pending-pod descriptions, container logs, and events for a
# namespace. Best-effort: every command tolerates failure so a debug dump never
# masks the original error.
dump_namespace_debug() {
  local namespace="$1"

  echo "----- DEBUG: namespace ${namespace} -----"
  echo "[helm releases]"
  helm list -n "${namespace}" || true

  echo "[workloads]"
  kubectl get statefulset,deployment,pod -n "${namespace}" -o wide || true

  local pending_pods
  pending_pods=$(kubectl get pods -n "${namespace}" --field-selector=status.phase=Pending -o name 2>/dev/null || true)
  if [[ -n "${pending_pods}" ]]; then
    echo "[pending pod descriptions]"
    while IFS= read -r pod; do
      [[ -z "${pod}" ]] && continue
      echo "### kubectl describe ${pod} -n ${namespace}"
      kubectl describe "${pod}" -n "${namespace}" || true
    done <<< "${pending_pods}"
  fi

  echo "[pod logs]"
  local pods
  pods=$(kubectl get pods -n "${namespace}" -o name 2>/dev/null || true)
  while IFS= read -r pod; do
    [[ -z "${pod}" ]] && continue
    echo "### kubectl logs ${pod} -n ${namespace} --all-containers --tail=200"
    kubectl logs "${pod}" -n "${namespace}" --all-containers --tail=200 2>&1 || true
    local prev
    prev=$(kubectl logs "${pod}" -n "${namespace}" --all-containers --previous --tail=200 2>/dev/null || true)
    if [[ -n "${prev}" ]]; then
      echo "### kubectl logs ${pod} -n ${namespace} --all-containers --previous --tail=200"
      printf '%s\n' "${prev}"
    fi
  done <<< "${pods}"

  echo "[events]"
  kubectl get events -n "${namespace}" --sort-by=.metadata.creationTimestamp || true
  echo "----- END DEBUG: namespace ${namespace} -----"
}

# Wait for a workload (Deployment or StatefulSet) to finish rolling out.
#
# Usage:
#   wait_rollout <namespace> <resource> [timeout]
#
# <resource> is a kubectl ref such as deployment/firebolt-gateway or
# statefulset/firebolt-engine-default-node-0. On timeout it dumps namespace
# debug and returns non-zero.
wait_rollout() {
  local namespace="$1"
  local resource="$2"
  local timeout="${3:-300s}"

  echo "Waiting for ${resource} in namespace ${namespace} to roll out (timeout ${timeout})..."
  if kubectl rollout status "${resource}" -n "${namespace}" --timeout="${timeout}"; then
    echo "${resource} rolled out in namespace ${namespace}"
    return 0
  fi

  echo "Timed out waiting for ${resource} in namespace ${namespace}"
  kubectl describe "${resource}" -n "${namespace}" || true
  dump_namespace_debug "${namespace}"
  return 1
}

# Run a query through the instance gateway and assert the result contains an
# expected substring. Mirrors the curl example in docs/quickstart.mdx: the
# gateway Service is <release>-gateway in the same namespace, and the target
# engine is selected via the X-Firebolt-Engine header.
#
# Usage:
#   run_query <namespace> <gateway-service> <engine> [query] [expected] [attempts] [sleep]
#
# A rolled-out engine can still need a few seconds before the gateway routes
# queries to it (engine HTTP listener warming up), so this polls.
run_query() {
  local namespace="$1"
  local gateway="$2"
  local engine="$3"
  local query="${4:-SELECT 1}"
  local expected="${5:-1}"
  local attempts="${6:-24}"
  local sleep_seconds="${7:-5}"

  echo "Running query against ${gateway} (engine=${engine}) in namespace ${namespace}: ${query}"

  local output=""
  for i in $(seq 1 "${attempts}"); do
    # Unique pod name per attempt: --rm deletes the pod on a clean attach, but
    # an attempt that errors out can leave the pod behind and collide on retry.
    local pod
    pod="query-$(date +%s)-${RANDOM}"
    if output=$(kubectl run "${pod}" --rm -i --restart=Never \
        --image=curlimages/curl --quiet -n "${namespace}" -- \
        curl --silent --show-error --fail-with-body \
        "http://${gateway}/" \
        -H "X-Firebolt-Engine: ${engine}" \
        -H "Content-Type: text/plain" \
        --data-binary "${query}" 2>/dev/null); then
      if printf '%s' "${output}" | grep -q "${expected}"; then
        echo "Query succeeded after ${i} attempt(s); result contains '${expected}':"
        printf '%s\n' "${output}"
        return 0
      fi
    fi
    echo "  attempt ${i}/${attempts}: no '${expected}' in result yet (sleep ${sleep_seconds}s)"
    sleep "${sleep_seconds}"
  done

  echo "Timed out running query against ${gateway} in namespace ${namespace}"
  echo "last output: ${output:-<none>}"
  dump_namespace_debug "${namespace}"
  return 1
}

# Current pipeline phase and the failure_reason to report if this phase fails.
# Both helm-test.sh (human output) and scripts/agent/up.sh (JSON output) walk the same
# phases via deploy_and_verify; scripts/agent/up.sh reads these globals in its EXIT trap
# to classify success vs. the specific failure mode. set_phase logs a marker to
# whatever stdout currently points at (the terminal/CI log in text mode, stderr
# in agent JSON mode, where stdout is reserved for the result object).
CURRENT_PHASE="init"
CURRENT_REASON="init_failed"
set_phase() {
  CURRENT_PHASE="$1"
  CURRENT_REASON="${2:-${1}_failed}"
  echo "--- phase: ${CURRENT_PHASE} ---"
}

# Deploy the chart against the floci S3 emulator and prove a query reaches the
# engine through the gateway. This is the single shared end-to-end sequence:
# the CI PR gate (helm-test.sh) and the agent entrypoints (scripts/agent/up.sh,
# verify.sh) all call it, so they exercise identical deploy/rollout/query logic.
# It assumes a reachable cluster (the caller creates or reuses one) and walks the
# quickstart: namespace -> floci + bucket -> helm install/upgrade -> per-workload
# rollout -> query.
#
# Usage:
#   deploy_and_verify <namespace> <release> <chart_dir> <engine_name> <mode> [values_file...]
#
# <mode> is "install" (clean) or "upgrade" (in place). Trailing args are extra
# helm values files supplied by the caller (its own sizing overlay) — this
# function adds no workflow-specific values beyond the floci storage block.
#
# On any failure it dumps namespace debug (to the current stdout) and returns
# non-zero with CURRENT_PHASE/CURRENT_REASON set to the failing step.
deploy_and_verify() {
  local namespace="$1"
  local release="$2"
  local chart_dir="$3"
  local engine="${4:-default}"
  # mode: "install" (default) clean-installs, uninstalling any stale release and
  # dropping its PVCs first; "upgrade" applies the chart in place with
  # `helm upgrade --install`, reusing the running release and its PVCs (the fast
  # iteration path — only workloads whose checksum/config changed get rolled).
  local mode="${5:-install}"
  # Any remaining args are extra helm values files the CALLER supplies (e.g. the
  # CI sizing overlay scripts/ci/values.yaml, or the agent's local overlay
  # scripts/agent/values.yaml). This function bakes in no workflow-specific
  # values of its own — only the floci storage block every floci-backed deploy
  # needs — so CI and agent inputs never leak into one another.
  shift 5
  local extra_values=("$@")

  # This lib lives at scripts/lib/; repo_root is two levels up (for local-floci.yaml).
  local lib_dir repo_root gateway
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${lib_dir}/../.." && pwd)"
  gateway="${release}-gateway"

  # --- Namespace (quickstart: "Create a namespace") -------------------------
  set_phase namespace
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -

  # --- Object storage (quickstart: "Deploy object storage") -----------------
  # local-floci.yaml carries the floci Deployment, its Service, and the
  # bucket-create Job. The engine refuses to start until the bucket exists.
  set_phase floci floci_not_ready
  echo "Deploying floci S3 emulator and creating the firebolt-managed bucket..."
  kubectl apply -n "${namespace}" -f "${repo_root}/local-floci.yaml"
  kubectl -n "${namespace}" rollout status deployment/floci --timeout=120s
  kubectl -n "${namespace}" wait --for=condition=complete job/floci-mkbucket --timeout=120s

  # --- Engine config (quickstart: "Configure the engine") -------------------
  # The my-values.yaml the quickstart tells the user to write, pointing managed
  # storage at the in-cluster floci endpoint.
  local my_values
  my_values="$(mktemp)"
  trap 'rm -f "'"${my_values}"'"' RETURN
  cat > "${my_values}" <<EOF
customEngineConfig:
  storage:
    type: minio
    api_scheme: "s3://"
    bucket_name: firebolt-managed
    minio:
      endpoint: http://floci.${namespace}.svc.cluster.local:4566
EOF

  # Helm value args: the floci storage block (always), then each caller-supplied
  # overlay in order. The caller owns its sizing overlay — CI passes
  # values.yaml, the agent passes scripts/agent/values.yaml.
  local value_args=(-f "${my_values}")
  local vf
  for vf in "${extra_values[@]}"; do
    value_args+=(-f "${vf}")
  done

  # --- Install / upgrade (quickstart: "Install the chart") ------------------
  # No --wait: a fresh engine pull is multi-GB, so readiness is polled per
  # workload below (with a debug dump on timeout) rather than blocking the call.
  if [[ "${mode}" == "upgrade" ]]; then
    # Fast iteration: apply the chart in place. The chart's checksum/config
    # annotations roll exactly the pods whose effective config changed, so an
    # unchanged engine is left running (no cold restart). --install also covers
    # the case where the release was never created on this cluster.
    set_phase upgrade helm_upgrade_failed
    echo "Upgrading the chart in place in ${namespace} (reusing release and PVCs)..."
    helm upgrade --install "${release}" "${chart_dir}" \
      --namespace "${namespace}" \
      "${value_args[@]}" || {
        echo "helm upgrade failed (an immutable-field change may need a clean 'make agent-up')"
        dump_namespace_debug "${namespace}"
        return 1
      }
  else
    # Clean install: helm install refuses to reuse a release name, so uninstall
    # any same-named release and drop its PVCs first so the engine also starts
    # against a fresh disk (a reused, full cache PVC trips its "not enough disk
    # space" evictor check). On a fresh cluster this is a no-op.
    set_phase install helm_install_failed
    if helm status "${release}" --namespace "${namespace}" >/dev/null 2>&1; then
      echo "Release ${release} already exists in ${namespace}; uninstalling it for a clean run..."
      helm uninstall "${release}" --namespace "${namespace}" --wait || true
      kubectl delete pvc --namespace "${namespace}" --all --ignore-not-found
    fi
    echo "Installing the chart into ${namespace}..."
    helm install "${release}" "${chart_dir}" \
      --namespace "${namespace}" \
      "${value_args[@]}" || {
        echo "helm install failed"
        dump_namespace_debug "${namespace}"
        return 1
      }
  fi

  # --- Verify the install (quickstart: "Verify the install") ----------------
  # The engine gets a longer budget: its first start pulls the multi-GB image.
  set_phase rollout rollout_timeout
  kubectl -n "${namespace}" get statefulset,deployment
  wait_rollout "${namespace}" "statefulset/${release}-metadata-pg"
  wait_rollout "${namespace}" "deployment/${release}-metadata-service"
  wait_rollout "${namespace}" "deployment/${release}-gateway"
  wait_rollout "${namespace}" "statefulset/${release}-engine-${engine}-node-0" "900s"

  # --- Run a query (quickstart: "Run a query") ------------------------------
  # Fast functional gate: prove the gateway routes a query to the engine. This
  # also absorbs the engine's post-rollout warm-up before the (optional) suite.
  set_phase query query_failed
  run_query "${namespace}" "${gateway}" "${engine}"

  # --- Thorough verification (opt-in) ---------------------------------------
  # THOROUGH=true additionally runs the chart's full helm test suite
  # (helm/templates/tests/*.yaml): DNS for every service, configmaps, postgres,
  # metadata service, engine-pods-reachable, auth, plus its own SELECT 1. An
  # iterating agent opts in when its change warrants broader coverage; the fast
  # query above stays the default for the tight loop.
  if [[ "${THOROUGH:-false}" == "true" ]]; then
    set_phase helm_test helm_test_failed
    echo "THOROUGH=true: running the chart's helm test suite..."
    helm test "${release}" --namespace "${namespace}" --logs || {
      echo "helm test suite failed"
      dump_namespace_debug "${namespace}"
      return 1
    }
  fi
}

# --- Agent JSON output plumbing ---------------------------------------------
# Shared by scripts/agent/{up,verify,down}.sh. In the default OUTPUT=json mode
# the agent entrypoints reserve stdout for a single result object and route all
# human/debug output to stderr; OUTPUT=text leaves the streams alone (behaving
# like helm-test.sh). AGENT_OUTPUT defaults to "json".
AGENT_OUTPUT="${OUTPUT:-json}"

# Reserve stdout (saved as fd 3) for the result object and send everything else
# to stderr. Call once near the top of an agent entrypoint, before any output.
agent_json_init() {
  if [[ "${AGENT_OUTPUT}" == "json" ]]; then
    exec 3>&1
    exec 1>&2
  fi
}

# Emit the deploy result (up.sh / verify.sh) on every exit path and re-exit with
# the original code. Reads $? first, then CURRENT_PHASE/CURRENT_REASON (advanced
# by deploy_and_verify). Args: cluster namespace release engine.
agent_emit_deploy_result() {
  local code=$?
  trap - EXIT
  local cluster="$1" namespace="$2" release="$3" engine="$4"
  local status reason_json verify_mode="fast"
  [[ "${THOROUGH:-false}" == "true" ]] && verify_mode="thorough"
  if [[ "${code}" -eq 0 ]]; then
    status="success"; reason_json="null"
  else
    status="failure"; reason_json="\"${CURRENT_REASON}\""
  fi
  if [[ "${AGENT_OUTPUT}" == "json" ]]; then
    printf '{"schema_version":"1","status":"%s","phase":"%s","failure_reason":%s,"verify_mode":"%s","cluster":"%s","namespace":"%s","release":"%s","engine":"%s","gateway_service":"%s","exit_code":%d}\n' \
      "${status}" "${CURRENT_PHASE}" "${reason_json}" "${verify_mode}" "${cluster}" \
      "${namespace}" "${release}" "${engine}" "${release}-gateway" "${code}" >&3
  fi
  exit "${code}"
}

# Emit the teardown result (down.sh). Args: cluster.
agent_emit_teardown_result() {
  local code=$?
  trap - EXIT
  local cluster="$1"
  local status reason_json
  if [[ "${code}" -eq 0 ]]; then
    status="success"; reason_json="null"
  else
    status="failure"; reason_json="\"teardown_failed\""
  fi
  if [[ "${AGENT_OUTPUT}" == "json" ]]; then
    printf '{"schema_version":"1","status":"%s","phase":"teardown","failure_reason":%s,"cluster":"%s","exit_code":%d}\n' \
      "${status}" "${reason_json}" "${cluster}" "${code}" >&3
  fi
  exit "${code}"
}
