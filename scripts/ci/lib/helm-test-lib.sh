#!/usr/bin/env bash
# Shared helpers for the firebolt-instance quickstart end-to-end check.
#
# Sourced by scripts/ci/helm-test.sh. The functions here wait for the
# chart's workloads to roll out and prove a query reaches an engine through the
# Envoy gateway, mirroring docs/quickstart.mdx. They also dump namespace state
# on failure: the CI kind cluster is destroyed when the job ends, so anything
# not printed here is lost.

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
