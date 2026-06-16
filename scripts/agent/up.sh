#!/usr/bin/env bash
# Agentic entrypoint: take a clean machine to a running Firebolt instance on a
# local kind cluster, then prove a query reaches the engine. This is the
# clean-slate command — it does a fresh `helm install`, dropping any stale
# release and its PVCs first. For fast iteration on an already-running instance
# use `make agent-verify` (in-place `helm upgrade`), which is much quicker.
#
# Contract (shared by up.sh / verify.sh / down.sh):
#   * Exit code is authoritative: 0 = instance up and serving queries, non-zero
#     = failure (the JSON names the phase).
#   * In the default JSON mode, stdout carries exactly ONE line: the result
#     object; ALL human/debug logging goes to stderr. Capture with
#     `make agent-up 2>/dev/null` and parse stdout.
#
# Result schema (stdout, JSON mode):
#   {"schema_version":"1","status":"success|failure","phase":"<last phase>",
#    "failure_reason":null|"<reason>","cluster":"...","namespace":"...",
#    "release":"...","engine":"...","gateway_service":"...","exit_code":N}
#
# Phases (also the failure_reason values): cluster_setup_failed, floci_not_ready,
# helm_install_failed, rollout_timeout, query_failed.
#
# Environment overrides:
#   OUTPUT                "json" (default) or "text" (behave like helm-test.sh)
#   THOROUGH              "true" also runs the chart's full helm test suite after
#                         the smoke query (default: false — fast query only)
#   KIND_CLUSTER          kind cluster name (default: firebolt-instance-helm)
#   NAMESPACE / RELEASE   target namespace / helm release (default: firebolt)
#   ENGINE_NAME           engine selected by the query (default: default)
#   CHART_DIR             chart to install (default: <repo>/helm)
#   GHCR_PACKAGES_PUBLIC  pull images directly from upstream (default: true)
#   NODE_IMAGE            kind node image (default: pinned in setup-kind-cluster.sh)
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

# The agent path is public-images only; fail fast (as JSON) on the private path.
assert_public_packages

echo "=== agent-up (cluster=${KIND_CLUSTER}, namespace=${NAMESPACE}, release=${RELEASE}) ==="

# --- Cluster (create or reuse a matching kind cluster) ----------------------
# Public images only (asserted above), so the kind nodes pull directly from
# upstream — no local registry or containerd mirror is set up.
set_phase cluster cluster_setup_failed
NODE_IMAGE="${NODE_IMAGE:-}" GHCR_PACKAGES_PUBLIC=true \
  "${LIB_DIR}/setup-kind-cluster.sh" "${KIND_CLUSTER}"

# --- Deploy + verify (clean install, layering the agent's local sizing) -----
deploy_and_verify "${NAMESPACE}" "${RELEASE}" "${CHART_DIR}" "${ENGINE_NAME}" install "${AGENT_VALUES}"

echo "✅ agent-up: Firebolt instance is running and serving queries (namespace=${NAMESPACE})"
# Success result is emitted by the EXIT trap.
