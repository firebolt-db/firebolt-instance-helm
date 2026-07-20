#!/usr/bin/env bash
# Create (or reuse) a kind cluster for the quickstart end-to-end check and wire
# its containerd to pull through the local OCI registry. Ported from
# firebolt-kubernetes-operator's scripts/setup-kind-cluster.sh.
#
# PREREQUISITE: the Docker daemon needs its memlock ulimit raised so the
# engine's io_uring works. Add to /etc/docker/daemon.json:
#
#   { "default-ulimits": { "memlock": { "Name": "memlock", "Hard": -1, "Soft": -1 } } }
#
# then restart Docker. The Helm Test workflow does this in a setup step.
set -euo pipefail

CLUSTER_NAME="${1:-firebolt-instance-helm}"
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/kind-config.yaml"

# Pin the Kubernetes version via the kind node image (digest-pinned, as kind
# requires). v1.35.0 is the default for kind v0.31.0 and is accepted by v0.32.0
# too. Requires a recent kind (>= v0.31); an older kind cannot boot this image.
NODE_IMAGE="${NODE_IMAGE:-kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f}"

# Local OCI registry that the kind node uses as a transparent mirror for the
# registries referenced by chart defaults. Defaults match
# scripts/setup-local-registry.sh.
REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
# In-cluster endpoint the kind node uses to reach the registry, resolved
# through Docker's embedded DNS on the "kind" network.
REGISTRY_ENDPOINT="http://${REGISTRY_NAME}:5000"
# Upstreams we mirror. Every workload image is pushed into the local registry
# under its upstream path (firebolt-db/engine, library/postgres,
# envoyproxy/envoy, ...), so one hosts.toml per upstream makes pulls transparent.
MIRRORED_HOSTS=("ghcr.io" "docker.io" "oci.firebolt.io")

# When "true" the ghcr.io/firebolt-db packages are public, so the kind nodes
# pull every image directly from upstream and we skip both the local registry
# and the containerd mirror wiring. Defaults to private (mirror through the
# local registry).
GHCR_PACKAGES_PUBLIC="${GHCR_PACKAGES_PUBLIC:-false}"

echo "=== Setting up kind cluster: ${CLUSTER_NAME} ==="

if ! command -v kind &> /dev/null; then
  echo "Error: kind is not installed. Please install kind first." >&2
  exit 1
fi

# Write /etc/containerd/certs.d/<host>/hosts.toml on every kind node, aliasing
# each mirrored upstream to the local registry. containerd hot-reloads this
# directory because kind-config.yaml sets
# `config_path = "/etc/containerd/certs.d"`, so no daemon restart is needed.
# Idempotent: re-running overwrites the same content.
configure_mirrors() {
  local nodes
  # configure_mirrors is only called on the private-package path, where the
  # containerd mirror is mandatory: without it, in-cluster pulls of the private
  # ghcr.io/firebolt-db images fall through to upstream and fail with 401. If we
  # cannot enumerate the nodes to wire, fail fast instead of leaving the cluster
  # in a state that looks ready but cannot pull the engine/metadata images.
  if ! nodes="$(kind get nodes --name "${CLUSTER_NAME}" 2>/dev/null)" || [ -z "${nodes}" ]; then
    echo "Error: could not list kind nodes for cluster '${CLUSTER_NAME}'; cannot wire the containerd registry mirror." >&2
    echo "       Private ghcr.io/firebolt-db image pulls would fail with 401 inside the cluster. Aborting." >&2
    return 1
  fi

  echo "Wiring containerd mirrors on each kind node -> ${REGISTRY_ENDPOINT}"
  for node in ${nodes}; do
    for host in "${MIRRORED_HOSTS[@]}"; do
      local certs_dir="/etc/containerd/certs.d/${host}"
      docker exec "${node}" mkdir -p "${certs_dir}"
      # No `server = ...` line: with `server` unset the upstream stays the
      # implicit fallback for public images (postgres, envoy, busybox, curl)
      # in case a registry pull misses. The private engine / metadata images
      # are always pushed into the registry, so they never hit that fallback.
      docker exec -i "${node}" sh -c "cat > ${certs_dir}/hosts.toml" <<EOF
[host."${REGISTRY_ENDPOINT}"]
  capabilities = ["pull", "resolve"]
EOF
    done
  done
}

# Pre-flight: the local registry must exist and be attached to the "kind"
# network BEFORE we wire containerd to mirror through it, otherwise containerd
# starts with hosts.toml pointing at an unreachable host. setup-local-registry.sh
# is idempotent; running it here is cheap when the registry is already up.
# Skipped when the packages are public — the nodes pull directly from upstream.
if [ "${GHCR_PACKAGES_PUBLIC}" != "true" ]; then
  "${SCRIPT_DIR}/setup-local-registry.sh"
fi

create_cluster() {
  echo "Creating kind cluster '${CLUSTER_NAME}' (node image ${NODE_IMAGE})..."
  kind create cluster --name "${CLUSTER_NAME}" --image "${NODE_IMAGE}" --config "${CONFIG}" --wait 120s
}

# Desired Kubernetes major.minor, parsed from the NODE_IMAGE tag (v1.35.0 -> 1.35).
DESIRED_K8S_MM="$(printf '%s\n' "${NODE_IMAGE#*:}" | sed -E 's/^v?([0-9]+\.[0-9]+).*/\1/')"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  # Reuse only if the existing cluster matches what we'd create. Two create-time
  # properties cannot be retrofitted, so a mismatch means recreate:
  #   1. config_path: a cluster created without the containerdConfigPatches
  #      ignores /etc/containerd/certs.d, so the registry mirror is inert and
  #      private-image pulls fall through to ghcr.io (401).
  #   2. Kubernetes version: the node image / K8s version is fixed at create.
  recreate_reason=""
  if [ "${GHCR_PACKAGES_PUBLIC}" != "true" ] && ! docker exec "${CONTROL_PLANE}" \
        grep -q 'config_path = "/etc/containerd/certs.d"' \
        /etc/containerd/config.toml 2>/dev/null; then
    recreate_reason="missing local-registry mirror config (no config_path in containerd)"
  else
    current_kubelet="$(kubectl --context "kind-${CLUSTER_NAME}" get nodes \
      -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
    current_mm="$(printf '%s\n' "${current_kubelet}" | sed -E 's/^v?([0-9]+\.[0-9]+).*/\1/')"
    if [ -n "${current_mm}" ] && [ "${current_mm}" != "${DESIRED_K8S_MM}" ]; then
      recreate_reason="Kubernetes version mismatch (have ${current_mm}, want ${DESIRED_K8S_MM})"
    fi
  fi

  if [ -z "${recreate_reason}" ]; then
    echo "Kind cluster '${CLUSTER_NAME}' already exists with the registry-mirror config and K8s ${DESIRED_K8S_MM}. Reusing it."
  else
    echo "Kind cluster '${CLUSTER_NAME}' exists but needs recreation: ${recreate_reason}." >&2
    kind delete cluster --name "${CLUSTER_NAME}"
    create_cluster
  fi
else
  create_cluster
fi

echo "Waiting for nodes to be Ready..."
kubectl --context "kind-${CLUSTER_NAME}" wait --for=condition=Ready node --all --timeout=120s

# Wire containerd to the local registry. Done after nodes are Ready so the node
# containers are running and `kind get nodes` returns the full set. Skipped when
# the packages are public — the nodes resolve every image upstream directly.
if [ "${GHCR_PACKAGES_PUBLIC}" = "true" ]; then
  echo "GHCR_PACKAGES_PUBLIC=true: kind nodes pull images directly; skipping registry-mirror wiring."
else
  configure_mirrors
fi

echo "=== Kind cluster '${CLUSTER_NAME}' is ready ==="
kubectl --context "kind-${CLUSTER_NAME}" get nodes
