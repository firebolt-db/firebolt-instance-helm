#!/usr/bin/env bash
# End-to-end check that walks docs/quickstart.mdx against the chart on this
# branch: deploy the floci S3 emulator, install the chart pointed at it, wait
# for every workload to roll out, and prove a query reaches the engine through
# the gateway. Run by .github/workflows/helm-test.yaml on every PR, and
# locally against a kind cluster via `make e2e`.
#
# The quickstart installs the published OCI chart; here we install the local
# ./helm directory so the PR's chart is what gets exercised. The only other
# departure is scripts/ci/ci-values.yaml, which trims engine and gateway
# resources to fit a 2-vCPU GitHub runner (see that file). Everything else
# follows the documented steps verbatim.
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
# shellcheck source=lib/helm-test-lib.sh
source "${SCRIPT_DIR}/lib/helm-test-lib.sh"

NAMESPACE="${NAMESPACE:-firebolt}"
RELEASE="${RELEASE:-firebolt}"
ENGINE_NAME="${ENGINE_NAME:-default}"
CHART_DIR="${CHART_DIR:-${REPO_ROOT}/helm}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

GATEWAY_SERVICE="${RELEASE}-gateway"

echo "=== helm-test (namespace=${NAMESPACE}, release=${RELEASE}, chart=${CHART_DIR}) ==="

# --- Create a namespace (quickstart: "Create a namespace") ------------------
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# --- Deploy object storage (quickstart: "Deploy object storage") ------------
# The quickstart applies local-floci.yaml from a raw GitHub URL; CI applies the
# copy on this branch so a change to it is what gets tested. local-floci.yaml
# carries the floci Deployment, its Service, and the firebolt-managed bucket
# Job. The engine refuses to start until the bucket exists, so wait for both.
echo "Deploying floci S3 emulator and creating the firebolt-managed bucket..."
kubectl apply -n "${NAMESPACE}" -f "${REPO_ROOT}/local-floci.yaml"
kubectl -n "${NAMESPACE}" rollout status deployment/floci --timeout=120s
kubectl -n "${NAMESPACE}" wait --for=condition=complete job/floci-mkbucket --timeout=120s

# --- Configure the engine (quickstart: "Configure the engine") --------------
# This is the my-values.yaml the quickstart tells the user to write, verbatim.
# It points the engine's managed storage at the in-cluster floci endpoint.
MY_VALUES="$(mktemp)"
trap 'rm -f "${MY_VALUES}"' EXIT
cat > "${MY_VALUES}" <<EOF
customEngineConfig:
  storage:
    type: minio
    api_scheme: "s3://"
    bucket_name: firebolt-managed
    minio:
      endpoint: http://floci.${NAMESPACE}.svc.cluster.local:4566
EOF

# Make the check re-runnable. `helm install` refuses to reuse a release name,
# so a leftover release from a prior run (or a manual `make dev`) would fail
# the install with "cannot re-use a name that is still in use". Uninstall any
# same-named release and drop its PVCs first, so the engine also starts against
# a fresh disk — a reused, full cache PVC trips its "not enough disk space"
# evictor check. A fresh CI cluster has neither, so this is a no-op there.
if helm status "${RELEASE}" --namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Release ${RELEASE} already exists in ${NAMESPACE}; uninstalling it for a clean run..."
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" --wait || true
  kubectl delete pvc --namespace "${NAMESPACE}" --all --ignore-not-found
fi

# --- Install the chart (quickstart: "Install the chart") --------------------
# my-values.yaml is the documented input; ci-values.yaml only resizes the
# engine and gateway to fit the runner. No `--wait`: the engine image is
# multi-GB and pulls at install time, so readiness is polled per workload
# below (with a debug dump on timeout) rather than blocking the install call.
echo "Installing the chart into ${NAMESPACE}..."
helm install "${RELEASE}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  -f "${MY_VALUES}" \
  -f "${SCRIPT_DIR}/ci-values.yaml" || {
    echo "helm install failed"
    dump_namespace_debug "${NAMESPACE}"
    exit 1
  }

# --- Verify the install (quickstart: "Verify the install") ------------------
# Wait for the same workloads the quickstart tells the user to watch. The
# engine gets a longer budget: its first start pulls the multi-GB image.
kubectl -n "${NAMESPACE}" get statefulset,deployment
wait_rollout "${NAMESPACE}" "statefulset/${RELEASE}-metadata-pg"
wait_rollout "${NAMESPACE}" "deployment/${RELEASE}-metadata-service"
wait_rollout "${NAMESPACE}" "deployment/${RELEASE}-gateway"
wait_rollout "${NAMESPACE}" "statefulset/${RELEASE}-engine-${ENGINE_NAME}-node-0" "900s"

# --- Run a query (quickstart: "Run a query") --------------------------------
# Prove the engine is actually serving queries through the gateway, not just
# rolled out. Same curl example the docs tell users to run.
run_query "${NAMESPACE}" "${GATEWAY_SERVICE}" "${ENGINE_NAME}"

echo "✅ helm-test passed (namespace=${NAMESPACE})"

# --- Clean up (quickstart: "Clean up") --------------------------------------
if [[ "${SKIP_CLEANUP}" == "true" ]]; then
  echo "SKIP_CLEANUP=true; leaving namespace ${NAMESPACE} in place."
else
  echo "Cleaning up namespace ${NAMESPACE}..."
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" --ignore-not-found || true
  kubectl delete namespace "${NAMESPACE}" --wait=false || true
fi
