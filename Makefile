RELEASE      ?= firebolt
NAMESPACE    ?= firebolt
CHART        := ./helm
VALUES_FILE  := $(CHART)/values.local.yaml
ECR_REGISTRY := 000000000000.dkr.ecr.us-east-1.amazonaws.com
AWS_REGION   := us-east-1

.DEFAULT_GOAL := help

.PHONY: help create install upgrade uninstall cleanup delete wait test test-cleanup check-pre-commit check-helm-docs setup-pre-commit docs lint

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

lint: ## Lint and template-render the helm chart
	helm lint --strict $(CHART)
	helm template $(RELEASE) $(CHART) > /dev/null
	@echo "All helm checks passed."

create: ## Create a local kind cluster
	kind create cluster

install: ## Install the chart into $(NAMESPACE) (creates namespace and ECR pull secret)
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret docker-registry regcred \
	      --docker-server=$(ECR_REGISTRY) \
	      --docker-username=AWS \
	      --docker-password=$$(aws ecr get-login-password --region $(AWS_REGION)) \
	      --namespace $(NAMESPACE) \
	      --dry-run=client -o yaml | kubectl apply -f -
	helm install $(RELEASE) $(CHART) --namespace $(NAMESPACE) \
	      -f $(VALUES_FILE)

upgrade: ## Upgrade the installed release with current chart and values
	helm upgrade $(RELEASE) $(CHART) --namespace $(NAMESPACE) -f $(VALUES_FILE)

uninstall: ## Uninstall the release and remove the ECR pull secret
	helm uninstall $(RELEASE) --namespace $(NAMESPACE)
	kubectl delete secret regcred --namespace $(NAMESPACE) --ignore-not-found

cleanup: ## Uninstall the release, delete PVCs, and remove the namespace
	-$(MAKE) uninstall
	kubectl delete pvc --namespace $(NAMESPACE) --all --ignore-not-found
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

wait: ## Wait for deployments and statefulsets in $(NAMESPACE) to roll out
	kubectl rollout status deployment --namespace $(NAMESPACE) --timeout=5m || true
	kubectl rollout status statefulset --namespace $(NAMESPACE) --timeout=5m || true

test: ## Run helm tests against the installed release
	helm test $(RELEASE) --namespace $(NAMESPACE) --logs

test-cleanup: ## Delete leftover helm test pods from previous runs
	@pods=$$(kubectl get pods -n $(NAMESPACE) -o name 2>/dev/null | grep "^pod/$(RELEASE)-test-" || true); \
	if [ -z "$$pods" ]; then \
	  echo "No stale test pods found."; \
	else \
	  echo "$$pods" | xargs kubectl delete -n $(NAMESPACE); \
	fi

delete: ## Delete the local kind cluster
	kind delete cluster
