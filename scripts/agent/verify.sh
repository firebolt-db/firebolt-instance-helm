#!/usr/bin/env bash
# Fast iteration entrypoint: apply the chart in place against an already-running
# instance and re-prove a query, so an agent can verify a chart edit in seconds
# without a teardown/reinstall. Uses `helm upgrade --install`, reusing the
# release and its PVCs — the chart's checksum/config annotations roll exactly
# the pods whose effective config changed (an unchanged engine is left running,
# no cold restart). The kind cluster is reused (created if absent).
#
# Use this in the inner loop:
#   vim helm/...               # edit the chart
#   make lint                  # tier 0: helm lint + template, no cluster (instant)
#   make agent-verify          # tier 1: helm upgrade + smoke query (seconds)
#   make agent-verify THOROUGH=true  # tier 1+: also run the full helm test suite
# The agent chooses depth per change: the fast smoke query for a narrow edit, or
# THOROUGH=true (DNS / configmaps / postgres / metadata / engine reachability /
# auth, via helm/templates/tests/*.yaml) when broader coverage is warranted.
# Fall back to `make agent-up` (clean reinstall) for changes helm upgrade cannot
# apply in place (immutable fields: StatefulSet volumeClaimTemplates, selectors)
# — those surface as failure_reason=helm_upgrade_failed.
#
# Same output contract and result schema as up.sh (JSON on stdout, logs on
# stderr; exit code authoritative). Phases / failure_reason values:
# cluster_setup_failed, floci_not_ready, helm_upgrade_failed, rollout_timeout,
# query_failed, helm_test_failed (THOROUGH only).
#
# Environment overrides: identical to up.sh (OUTPUT, THOROUGH, KIND_CLUSTER,
# NAMESPACE, RELEASE, ENGINE_NAME, CHART_DIR, GHCR_PACKAGES_PUBLIC, NODE_IMAGE).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# Shared deploy/verify + cluster-bringup machinery lives under scripts/lib.
LIB_DIR="${REPO_ROOT}/scripts/lib"
# shellcheck source=../lib/deploy.sh
source "${LIB_DIR}/deploy.sh"

KIND_CLUSTER="${KIND_CLUSTER:-firebolt-instance-helm}"
NAMESPACE="${NAMESPACE:-firebolt}"
RELEASE="${RELEASE:-firebolt}"
ENGINE_NAME="${ENGINE_NAME:-default}"
CHART_DIR="${CHART_DIR:-${REPO_ROOT}/helm}"
GHCR_PACKAGES_PUBLIC="${GHCR_PACKAGES_PUBLIC:-true}"
# The agent workflow's own local sizing overlay.
AGENT_VALUES="${AGENT_VALUES:-${SCRIPT_DIR}/values.yaml}"

agent_json_init
trap 'agent_emit_deploy_result "${KIND_CLUSTER}" "${NAMESPACE}" "${RELEASE}" "${ENGINE_NAME}"' EXIT

echo "=== agent-verify (cluster=${KIND_CLUSTER}, namespace=${NAMESPACE}, release=${RELEASE}) ==="

# --- Cluster (reuse the running cluster; create it if absent) ---------------
set_phase cluster cluster_setup_failed
NODE_IMAGE="${NODE_IMAGE:-}" \
  REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}" \
  REGISTRY_PORT="${REGISTRY_PORT:-5001}" \
  GHCR_PACKAGES_PUBLIC="${GHCR_PACKAGES_PUBLIC}" \
  "${LIB_DIR}/setup-kind-cluster.sh" "${KIND_CLUSTER}"

# --- Upgrade in place + verify (fast path, layering the agent's local sizing) -
deploy_and_verify "${NAMESPACE}" "${RELEASE}" "${CHART_DIR}" "${ENGINE_NAME}" upgrade "${AGENT_VALUES}"

echo "✅ agent-verify: chart upgraded in place and still serving queries (namespace=${NAMESPACE})"
# Success result is emitted by the EXIT trap.
