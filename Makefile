RELEASE      ?= firebolt
NAMESPACE    ?= firebolt
CHART        := ./helm
VALUES_FILE  := $(CHART)/values.local.yaml
ECR_REGISTRY := 000000000000.dkr.ecr.us-east-1.amazonaws.com
AWS_REGION   := us-east-1

.PHONY: create install upgrade uninstall cleanup delete wait test test-cleanup check-pre-commit check-helm-docs setup-pre-commit docs lint

check-pre-commit:
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "Error: pre-commit is not installed."; \
		echo "Install it from https://github.com/pre-commit/pre-commit"; \
		exit 1; \
	}

check-helm-docs:
	@command -v helm-docs >/dev/null 2>&1 || { \
		echo "Error: helm-docs is not installed."; \
		echo "Install it from https://github.com/norwoodj/helm-docs"; \
		exit 1; \
	}

setup-pre-commit: check-pre-commit check-helm-docs
	pre-commit install
	pre-commit install-hooks

docs: check-helm-docs
	helm-docs --chart-search-root=helm

lint:
	helm lint --strict $(CHART)
	helm template $(RELEASE) $(CHART) > /dev/null
	@echo "All helm checks passed."

create:
	kind create cluster

install:
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret docker-registry regcred \
	      --docker-server=$(ECR_REGISTRY) \
	      --docker-username=AWS \
	      --docker-password=$$(aws ecr get-login-password --region $(AWS_REGION)) \
	      --namespace $(NAMESPACE) \
	      --dry-run=client -o yaml | kubectl apply -f -
	helm install $(RELEASE) $(CHART) --namespace $(NAMESPACE) \
	      -f $(VALUES_FILE)

upgrade:
	helm upgrade $(RELEASE) $(CHART) --namespace $(NAMESPACE) -f $(VALUES_FILE)

uninstall:
	helm uninstall $(RELEASE) --namespace $(NAMESPACE)
	kubectl delete secret regcred --namespace $(NAMESPACE) --ignore-not-found

cleanup:
	-$(MAKE) uninstall
	kubectl delete pvc --namespace $(NAMESPACE) --all --ignore-not-found
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

wait:
	kubectl rollout status deployment --namespace $(NAMESPACE) --timeout=5m || true
	kubectl rollout status statefulset --namespace $(NAMESPACE) --timeout=5m || true

test:
	helm test $(RELEASE) --namespace $(NAMESPACE) --logs

test-cleanup:
	@pods=$$(kubectl get pods -n $(NAMESPACE) -o name 2>/dev/null | grep "^pod/$(RELEASE)-test-" || true); \
	if [ -z "$$pods" ]; then \
	  echo "No stale test pods found."; \
	else \
	  echo "$$pods" | xargs kubectl delete -n $(NAMESPACE); \
	fi

delete:
	kind delete cluster
