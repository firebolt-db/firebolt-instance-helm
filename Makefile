RELEASE      ?= firebolt
NAMESPACE    ?= firebolt
CHART        := ./helm
VALUES_FILE  := $(CHART)/values-dev.yaml
ECR_REGISTRY := 000000000000.dkr.ecr.us-east-1.amazonaws.com
AWS_REGION   := us-east-1
KIND_CLUSTER ?= firebolt-instance-helm

# Kubernetes version for the e2e kind cluster, pinned by digest as kind requires.
# Single source of truth: override on the CLI (`make prepare-test-e2e NODE_IMAGE=...`)
# or via the NODE_IMAGE env (the CI matrix sets it). Bump in one place here.
NODE_IMAGE ?= kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f

# Local Docker registry the kind node mirrors through (serves the private
# engine/metadata images locally so the node never anonymously pulls ghcr.io,
# and keeps a layer cache across cluster recreations). Override REGISTRY_PORT /
# REGISTRY_NAME if 5001 / kind-registry collide. Same defaults are baked into
# scripts/ci/setup-local-registry.sh.
REGISTRY_NAME ?= kind-registry
REGISTRY_PORT ?= 5001

# Set to "true" once the ghcr.io/firebolt-db engine + metadata packages are
# public. While "false" (private) the kind node mirrors the images through the
# local registry above (pulled once on the authenticated host). When "true" the
# kind nodes pull the images directly from upstream, so the local registry, the
# containerd mirror wiring, and the image-publishing step are all skipped.
GHCR_PACKAGES_PUBLIC ?= false

.DEFAULT_GOAL := help

.PHONY: help create install dev upgrade upgrade-dev uninstall cleanup delete test test-cleanup check-pre-commit check-helm-docs setup-pre-commit docs docs-check lint floci setup-local-registry cleanup-local-registry flush-local-registry setup-kind load-test-images prepare-test-e2e helm-test cleanup-test-e2e

help: ## Show this help message
	@printf '\033[33m%s\n' \
	' _____ ___ ____  _____ ____   ___  _     _____ ' \
	'|  ___|_ _|  _ \| ____| __ ) / _ \| |   |_   _|' \
	'| |_   | || |_) |  _| |  _ \| | | | |     | |  ' \
	'|  _|  | ||  _ <| |___| |_) | |_| | |___  | |  ' \
	'|_|   |___|_| \_\_____|____/ \___/|_____| |_|  '
	@printf '\033[0m\n'
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

check-pre-commit: ## Verify that pre-commit is installed
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "Error: pre-commit is not installed."; \
		echo "Install it from https://github.com/pre-commit/pre-commit"; \
		exit 1; \
	}

check-helm-docs: ## Verify that helm-docs is installed
	@command -v helm-docs >/dev/null 2>&1 || { \
		echo "Error: helm-docs is not installed."; \
		echo "Install it from https://github.com/norwoodj/helm-docs"; \
		exit 1; \
	}

setup-pre-commit: check-pre-commit check-helm-docs ## Install pre-commit hooks for this repo
	pre-commit install
	pre-commit install-hooks

docs: check-helm-docs ## Regenerate chart documentation with helm-docs
	helm-docs --chart-search-root=helm

docs-check: ## Validate Mintlify docs navigation (path depth and lost pages)
	$(MAKE) -C docs check

lint: ## Lint and template-render the helm chart
	helm lint --strict $(CHART)
	helm template $(RELEASE) $(CHART) > /dev/null
	@echo "All helm checks passed."

create: ## Create a local kind cluster
	kind create cluster

floci: ## Deploy floci S3 emulator + create the engine's managed_storage bucket in $(NAMESPACE)
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n $(NAMESPACE) -f local-floci.yaml
	kubectl rollout status deployment/floci -n $(NAMESPACE) --timeout=120s
	kubectl wait --for=condition=complete job/floci-mkbucket -n $(NAMESPACE) --timeout=120s

install: ## Install the chart into $(NAMESPACE) with chart defaults (no overlay)
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm install $(RELEASE) $(CHART) --namespace $(NAMESPACE)

dev: floci ## Install with the dev overlay: floci pre-step + ECR pull secret + values-dev.yaml
	kubectl create secret docker-registry regcred \
	      --docker-server=$(ECR_REGISTRY) \
	      --docker-username=AWS \
	      --docker-password=$$(aws ecr get-login-password --region $(AWS_REGION)) \
	      --namespace $(NAMESPACE) \
	      --dry-run=client -o yaml | kubectl apply -f -
	helm install $(RELEASE) $(CHART) --namespace $(NAMESPACE) \
	      -f $(VALUES_FILE)

upgrade: ## Upgrade the release with chart defaults (no overlay)
	helm upgrade $(RELEASE) $(CHART) --namespace $(NAMESPACE)

upgrade-dev: ## Upgrade the release with the dev values overlay
	helm upgrade $(RELEASE) $(CHART) --namespace $(NAMESPACE) -f $(VALUES_FILE)

uninstall: ## Uninstall the release and remove the ECR pull secret
	helm uninstall $(RELEASE) --namespace $(NAMESPACE)
	kubectl delete secret regcred --namespace $(NAMESPACE) --ignore-not-found

cleanup: ## Uninstall the release, delete PVCs, and remove the namespace
	-$(MAKE) uninstall
	kubectl delete pvc --namespace $(NAMESPACE) --all --ignore-not-found
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

test: ## Run helm tests against the installed release
	helm test $(RELEASE) --namespace $(NAMESPACE) --logs

setup-local-registry: ## Start the local Docker registry the kind node mirrors through (idempotent)
	@if [ "$(GHCR_PACKAGES_PUBLIC)" = "true" ]; then \
	  echo "GHCR_PACKAGES_PUBLIC=true: skipping local registry (kind nodes pull images directly)."; \
	else \
	  REGISTRY_NAME=$(REGISTRY_NAME) REGISTRY_PORT=$(REGISTRY_PORT) ./scripts/ci/setup-local-registry.sh; \
	fi

cleanup-local-registry: ## Stop and remove the local Docker registry container (cached images are lost)
	@docker rm -f $(REGISTRY_NAME) >/dev/null 2>&1 || true
	@echo "Removed local registry '$(REGISTRY_NAME)' (if it existed). Re-run 'make setup-local-registry' to recreate."

flush-local-registry: cleanup-local-registry setup-local-registry ## Recreate the local registry from scratch (drops cached images)

setup-kind: setup-local-registry ## Create (or reuse) the e2e kind cluster and wire it to the local registry
	@NODE_IMAGE='$(NODE_IMAGE)' REGISTRY_NAME=$(REGISTRY_NAME) REGISTRY_PORT=$(REGISTRY_PORT) GHCR_PACKAGES_PUBLIC=$(GHCR_PACKAGES_PUBLIC) ./scripts/ci/setup-kind-cluster.sh $(KIND_CLUSTER)

load-test-images: ## Pull the chart + floci images and push them into the local registry
	@if [ "$(GHCR_PACKAGES_PUBLIC)" = "true" ]; then \
	  echo "GHCR_PACKAGES_PUBLIC=true: skipping image publishing (kind nodes pull images directly)."; \
	else \
	  REGISTRY_NAME=$(REGISTRY_NAME) REGISTRY_PORT=$(REGISTRY_PORT) ./scripts/ci/load-e2e-images.sh $(KIND_CLUSTER); \
	fi

prepare-test-e2e: setup-kind load-test-images ## Full e2e setup: start the registry, create the kind cluster, publish images

helm-test: ## Run the quickstart end-to-end check against the current cluster (run prepare-test-e2e first)
	NAMESPACE=$(NAMESPACE) RELEASE=$(RELEASE) CHART_DIR=$(CHART) ./scripts/ci/helm-test.sh

cleanup-test-e2e: ## Tear down the e2e kind cluster (the local registry is left running; use flush-local-registry to drop it)
	kind delete cluster --name $(KIND_CLUSTER)

test-cleanup: ## Delete leftover helm test pods from previous runs
	@pods=$$(kubectl get pods -n $(NAMESPACE) -o name 2>/dev/null | grep "^pod/$(RELEASE)-test-" || true); \
	if [ -z "$$pods" ]; then \
	  echo "No stale test pods found."; \
	else \
	  echo "$$pods" | xargs kubectl delete -n $(NAMESPACE); \
	fi

delete: ## Delete the local kind cluster
	kind delete cluster
