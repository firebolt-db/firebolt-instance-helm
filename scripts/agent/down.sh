#!/usr/bin/env bash
# Teardown counterpart to up.sh: delete the kind cluster, returning the host to
# a clean state once an agent is done iterating. Deleting the cluster takes the
# namespace, release, PVCs, and floci with it, so this is a single idempotent
# step (deleting a cluster that does not exist is a no-op). The agent path runs
# on public images and never creates a local registry, so there is nothing else
# to clean up here.
#
# Same output contract as up.sh: JSON result on stdout, logs on stderr.
#
# Environment overrides:
#   OUTPUT            "json" (default) or "text"
#   KIND_CLUSTER      kind cluster to delete (default: firebolt-instance-helm)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../lib/deploy.sh
source "${REPO_ROOT}/scripts/lib/deploy.sh"

KIND_CLUSTER="${KIND_CLUSTER:-firebolt-instance-helm}"

agent_json_init
trap 'agent_emit_teardown_result "${KIND_CLUSTER}"' EXIT

echo "=== agent-down (cluster=${KIND_CLUSTER}) ==="

echo "Deleting kind cluster '${KIND_CLUSTER}' (takes the namespace, release, and PVCs with it)..."
kind delete cluster --name "${KIND_CLUSTER}"

echo "✅ agent-down: host returned to a clean state."
