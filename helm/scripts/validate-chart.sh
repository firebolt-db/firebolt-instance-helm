#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="$(dirname "$SCRIPT_DIR")"

echo "==================================="
echo "Helm Chart Validation"
echo "==================================="
echo ""

if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed. Please install helm first."
    exit 1
fi

if ! command -v yamllint &> /dev/null; then
    echo "ERROR: yamllint is not installed. Please install yamllint first."
    echo "  You can install it with: pip install yamllint"
    exit 1
fi

echo "✓ Required tools found: helm $(helm version --short), yamllint"
echo ""

echo "Step 0: Building chart dependencies..."
echo "-----------------------------------"
helm repo add bitnami https://charts.bitnami.com/bitnami
if helm dependency build "$HELM_DIR/"; then
    echo "✓ helm dependency build passed"
else
    echo "✗ helm dependency build failed"
    exit 1
fi
echo ""

echo "Step 1: Running yamllint on chart source files..."
echo "-----------------------------------"
if yamllint \
    "$HELM_DIR/Chart.yaml" \
    "$HELM_DIR/values.yaml"; then
    echo "✓ yamllint passed"
else
    echo "✗ yamllint failed"
    exit 1
fi
echo ""

echo "Step 2: Running helm lint..."
echo "-----------------------------------"
if helm lint "$HELM_DIR/"; then
    echo "✓ helm lint passed"
else
    echo "✗ helm lint failed"
    exit 1
fi
echo ""

echo "Step 3: Generating and validating helm template output..."
echo "-----------------------------------"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Generating template with default values..."
if ! helm template firebolt-instance "$HELM_DIR/" > "$TEMP_DIR/helm-template-output.yaml"; then
    echo "✗ Failed to generate template with default values"
    exit 1
fi

echo "Extracting firebolt-instance templates (excluding subcharts)..."
# Split the rendered output so we only lint our own templates, not third-party
# subcharts (e.g. Bitnami PostgreSQL) whose style we don't control.
csplit -z -f "$TEMP_DIR/doc-" "$TEMP_DIR/helm-template-output.yaml" '/^---$/' '{*}' > /dev/null
cat /dev/null > "$TEMP_DIR/firebolt-templates.yaml"
for f in "$TEMP_DIR"/doc-*; do
    if ! grep -q 'charts/postgresql' "$f"; then
        cat "$f" >> "$TEMP_DIR/firebolt-templates.yaml"
    fi
done

echo "Running yamllint on firebolt-instance templates..."
if yamllint "$TEMP_DIR/firebolt-templates.yaml"; then
    echo "✓ Template passed yamllint"
else
    echo "✗ Template failed yamllint"
    exit 1
fi
echo ""

echo "==================================="
echo "✓ All validation checks passed!"
echo "==================================="
