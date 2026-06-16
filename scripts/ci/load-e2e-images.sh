#!/usr/bin/env bash
# Publish every image the quickstart end-to-end check needs into the local
# Docker registry that the kind node mirrors through (started by
# scripts/setup-local-registry.sh, wired into containerd by
# scripts/setup-kind-cluster.sh). Ported from firebolt-kubernetes-operator's
# scripts/load-e2e-images.sh.
#
# Flow per image: if the registry already serves the target ref, skip it;
# otherwise docker pull (on the host) -> docker tag to the registry path ->
# docker push -> docker rmi (free the host's content store). The kind node then
# pulls each image from the local registry on demand, so it never does an
# anonymous upstream pull. The skip matters because the rmi empties the host
# content store, so without it a plain re-run re-pulls every image from upstream
# even though the registry already holds it; `make flush-local-registry` forces
# a clean re-pull.
#
# GHCR AUTHENTICATION IS REQUIRED for the pull step. The engine and metadata
# images live in the PRIVATE ghcr.io/firebolt-db org, so anonymous pulls 401.
# The host's Docker must be able to pull them before this script runs:
#   - Locally:  echo "$GITHUB_TOKEN" | docker login ghcr.io -u USERNAME --password-stdin
#   - In CI:    the runners already have GHCR access; no explicit login needed.
#
# The image set is derived, not hardcoded, so it stays in sync with the chart:
#   - rendered chart templates (engine, metadata, gateway, postgres, plus the
#     helm-test hook images — tags resolved against Chart.appVersion)
#   - local-floci.yaml (floci + aws-cli)
set -euo pipefail

CLUSTER_NAME="${1:-firebolt-instance-helm}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"
# Host-side endpoint that `docker push` talks to. The in-cluster endpoint
# (kind-registry:5000) is configured by setup-kind-cluster.sh.
REGISTRY_HOST_ENDPOINT="localhost:${REGISTRY_PORT}"

for tool in docker kind helm; do
  if ! command -v "${tool}" &>/dev/null; then
    echo "Error: ${tool} is not installed or not on PATH." >&2
    exit 1
  fi
done

if ! kind get nodes --name "${CLUSTER_NAME}" &>/dev/null; then
  echo "Error: kind cluster '${CLUSTER_NAME}' does not exist. Run 'make setup-kind' first." >&2
  exit 1
fi

# Pre-flight: the registry must be reachable on the host before we push.
# Clearer error than `docker push` failing with "connection refused".
# setup-local-registry.sh is shared cluster-bringup machinery under scripts/lib.
"${REPO_ROOT}/scripts/lib/setup-local-registry.sh" >/dev/null

# Strip a leading `image:` key and surrounding quotes from a YAML line.
strip_image_line() {
  sed -E 's/^[[:space:]]*image:[[:space:]]*//; s/^"//; s/"$//'
}

# Translate a Docker image reference to the path the kind-registry mirror
# expects, matching Docker's implicit normalisation:
#   ghcr.io/firebolt-db/engine:tag -> firebolt-db/engine:tag   (strip explicit host)
#   envoyproxy/envoy:v1.37.2       -> envoyproxy/envoy:v1.37.2  (org/name; keep)
#   postgres:16-alpine             -> library/postgres:16-alpine (official Docker Hub)
to_registry_path() {
  local image="$1"
  local first_seg="${image%%/*}"
  if [[ "${image}" == */* ]] && \
     [[ "${first_seg}" == *"."* || "${first_seg}" == *":"* || "${first_seg}" == "localhost" ]]; then
    printf '%s\n' "${image#*/}"          # has explicit host: strip it
  elif [[ "${image}" == */* ]]; then
    printf '%s\n' "${image}"             # org but no host (Docker Hub user image): keep
  else
    printf '%s\n' "library/${image}"     # bare name (Docker Hub official): prepend library/
  fi
}

echo "Collecting image references..."
images_raw="$(
  {
    helm template firebolt "${REPO_ROOT}/helm" \
      -f "${SCRIPT_DIR}/values.yaml" 2>/dev/null \
      | grep -E '^[[:space:]]*image:' | strip_image_line
    grep -E '^[[:space:]]*image:' "${REPO_ROOT}/local-floci.yaml" | strip_image_line
  } | sort -u
)"

if [ -z "${images_raw}" ]; then
  echo "Error: no image references found to load." >&2
  exit 1
fi

# Kind node architecture. The engine binary is x86-64-v3 / arm64-native; if a
# foreign-arch engine image is published, the node runs it under user-mode
# emulation (on Apple Silicon, qemu-x86_64, which lacks AVX2/BMI2/FMA), and the
# engine SIGILLs ~6 minutes into startup as an opaque probe timeout.
node_arch_kernel="$(docker exec "${CLUSTER_NAME}-control-plane" uname -m 2>/dev/null || echo unknown)"
case "${node_arch_kernel}" in
  x86_64)  NODE_ARCH=amd64 ;;
  aarch64) NODE_ARCH=arm64 ;;
  *)       NODE_ARCH="${node_arch_kernel}" ;;
esac

echo "=== Publishing images to local registry ${REGISTRY_HOST_ENDPOINT} ==="
while IFS= read -r img; do
  [ -z "${img}" ] && continue

  # Build the registry ref up-front. Drop any `@sha256:...` digest from the
  # target (docker tag rejects a digest target); the pushed manifest keeps the
  # same digest, so a digest-pinned workload reference still resolves through
  # the mirror.
  repo_path="$(to_registry_path "${img}")"
  registry_ref="${REGISTRY_HOST_ENDPOINT}/${repo_path%@*}"

  # Skip if the registry already serves this reference. The host content store
  # is emptied after every push (docker rmi below), so without this guard a
  # plain re-run re-pulls every image from upstream even though the registry
  # already holds it. The repo path carries at most one colon (the host is
  # stripped above), so the tag is whatever follows it; a digest-only ref is
  # pushed as :latest. `make flush-local-registry` forces a clean re-pull (and
  # re-runs the engine arch check below).
  push_ref="${repo_path%@*}"
  if [[ "${push_ref}" == *:* ]]; then
    manifest_name="${push_ref%:*}"; manifest_tag="${push_ref##*:}"
  else
    manifest_name="${push_ref}"; manifest_tag="latest"
  fi
  if curl -fsS -o /dev/null \
       -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
       -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
       -H "Accept: application/vnd.oci.image.manifest.v1+json" \
       -H "Accept: application/vnd.oci.image.index.v1+json" \
       "http://${REGISTRY_HOST_ENDPOINT}/v2/${manifest_name}/manifests/${manifest_tag}"; then
    echo "==> ${registry_ref} already in registry; skipping pull/tag/push."
    continue
  fi

  echo "==> docker pull ${img}"
  docker pull "${img}"

  # Engine image is the only one with the foreign-arch SIGILL trap; guard it.
  if [[ "${img}" == ghcr.io/firebolt-db/engine:* ]]; then
    img_arch="$(docker image inspect "${img}" --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
    if [ "${img_arch}" != "${NODE_ARCH}" ]; then
      echo "Error: engine image arch '${img_arch}' does not match kind node arch '${NODE_ARCH}'." >&2
      echo "       A foreign-arch engine runs under emulation in the node and SIGILLs at startup." >&2
      echo "       Pull a manifest-list/native-arch engine tag, or run on a matching-arch host." >&2
      exit 1
    fi
    echo "    engine image arch '${img_arch}' matches kind node arch '${NODE_ARCH}'."
  fi

  echo "==> docker tag ${img} -> ${registry_ref}"
  docker tag "${img}" "${registry_ref}"
  echo "==> docker push ${registry_ref}"
  docker push "${registry_ref}"

  # Free the host's content store; the bytes live in the registry now. Both
  # rmis tolerate "image in use" / "no such image".
  docker rmi "${registry_ref}" >/dev/null 2>&1 || true
  docker rmi "${img}" >/dev/null 2>&1 || true
done <<< "${images_raw}"

echo "=== Image publishing complete ==="
echo "Catalog of repositories in local registry ${REGISTRY_HOST_ENDPOINT}:"
curl -fsS "http://${REGISTRY_HOST_ENDPOINT}/v2/_catalog" | head -c 4096 || true
echo ""
