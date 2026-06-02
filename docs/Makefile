SHELL := bash

# .ONESHELL and multi-line recipes require GNU Make 4.2+ (.FEATURES includes "oneshell").
ifeq ($(filter oneshell,$(.FEATURES)),)
$(error \
  GNU Make 4.2+ is required (found: $(or $(MAKE_VERSION),non-GNU make)). \
  On macOS: brew install make, then run gmake or add \
  /opt/homebrew/opt/make/libexec/gnubin to PATH)
endif

.ONESHELL:
.PHONY:

.SHELLFLAGS := -euo pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

PYTHON ?= python3

.PHONY: default
default: check

.PHONY: check
check: test check-navigation check-lost-redirects
	@echo "☑ Helm Chart docs checks passed"

.PHONY: test
test:
	@echo "Running docs script tests..."
	$(PYTHON) scripts/test_check_helm_navigation.py
	$(PYTHON) scripts/test_check_lost_redirects.py
	@echo "☑ Docs script tests passed"

.PHONY: check-navigation
check-navigation:
	@echo "Checking navigation path depth (post-packdb aggregation rules)..."
	$(PYTHON) scripts/check_helm_navigation.py
	@echo "☑ Navigation path depth is valid"
	@echo "Checking for MDX files missing from navigation..."
	$(PYTHON) scripts/check_lost_pages.py
	@echo "☑ All MDX files are listed in navigation"

.PHONY: check-lost-redirects
check-lost-redirects:
	@echo "Checking removed pages have redirects (propagated into packdb)..."
	$(PYTHON) scripts/check_lost_redirects.py
	@echo "☑ No removed pages without a redirect"

.PHONY: check-lost-redirects-regenerate
check-lost-redirects-regenerate:
	$(PYTHON) scripts/check_lost_redirects.py regenerate
	@echo "☑ Regenerated known_pages.json"
