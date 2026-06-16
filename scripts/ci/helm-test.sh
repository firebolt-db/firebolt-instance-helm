#!/usr/bin/env bash
# End-to-end check that walks docs/quickstart.mdx against the chart on this
# branch: deploy the floci S3 emulator, install the chart pointed at it, wait
# for every workload to roll out, and prove a query reaches the engine through
# the gateway. Run by .github/workflows/helm-test.yaml on every PR, and locally
# against a kind cluster via `make helm-test` (after `make prepare-test-e2e`).
#
# The quickstart installs the published OCI chart; here we install the local
# ./helm directory so the PR's chart is what gets exercised. The only other
# departure is scripts/ci/values.yaml, which trims engine and gateway
# resources to fit a 2-vCPU GitHub runner (see that file). Everything else
# follows the documented steps verbatim.
#
# The deploy/install/rollout/query sequence lives in scripts/lib/deploy.sh
# (deploy_and_verify) so this PR gate and the agent entrypoint (scripts/agent/up.sh)
# run identical logic. This script adds the human-readable framing and cleanup;
# scripts/agent/up.sh adds cluster bootstrap and machine-parseable JSON output.
#
# Environment overrides:
#   NAMESPACE     target namespace (default: firebolt)
#   RELEASE       helm release name (default: firebolt)
#   ENGINE_NAME   engine selected by the query (default: default)
#   CHART_DIR     chart to install (default: <repo>/helm)
#   SKIP_CLEANUP  when "true", leave the namespace in place after a pass
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../lib/deploy.sh
source "${REPO_ROOT}/scripts/lib/deploy.sh"

NAMESPACE="${NAMESPACE:-firebolt}"
RELEASE="${RELEASE:-firebolt}"
ENGINE_NAME="${ENGINE_NAME:-default}"
CHART_DIR="${CHART_DIR:-${REPO_ROOT}/helm}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

echo "=== helm-test (namespace=${NAMESPACE}, release=${RELEASE}, chart=${CHART_DIR}) ==="

# Deploy and prove a query reaches the engine (shared deploy_and_verify), passing
# CI's own sizing overlay. The agent path passes its own overlay instead.
deploy_and_verify "${NAMESPACE}" "${RELEASE}" "${CHART_DIR}" "${ENGINE_NAME}" install "${SCRIPT_DIR}/values.yaml"

echo "✅ helm-test passed (namespace=${NAMESPACE})"

# --- Clean up (quickstart: "Clean up") --------------------------------------
if [[ "${SKIP_CLEANUP}" == "true" ]]; then
  echo "SKIP_CLEANUP=true; leaving namespace ${NAMESPACE} in place."
else
  echo "Cleaning up namespace ${NAMESPACE}..."
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" --ignore-not-found || true
  kubectl delete namespace "${NAMESPACE}" --wait=false || true
fi
