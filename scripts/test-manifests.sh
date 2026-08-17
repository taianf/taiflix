#!/usr/bin/env bash
# ==============================================================================
# scripts/test-manifests.sh - Linting & Validation for Helm charts & scripts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}==> Running Taiflix Repository Test & Validation Suite...${NC}"

# 1. Validate Python code syntax
echo -e "  Checking Python syntax..."
python3 -m py_compile scripts/wire-services.py
echo -e "  [${GREEN}✓${NC}] scripts/wire-services.py syntax valid"

# 2. Check Shell scripts
if command -v shellcheck >/dev/null 2>&1; then
    echo -e "  Running shellcheck on shell scripts..."
    mapfile -t SH_FILES < <(find . -maxdepth 2 -name "*.sh" -not -path "*/.*/*")
    if [[ ${#SH_FILES[@]} -gt 0 ]]; then
        shellcheck -x "${SH_FILES[@]}"
        echo -e "  [${GREEN}✓${NC}] Shell scripts passed shellcheck (${#SH_FILES[@]} files)"
    fi
fi

# 3. Lint Helm charts if Helm is installed
if command -v helm >/dev/null 2>&1; then
    echo -e "  Validating Helm charts..."
    for chart_dir in charts/*; do
        if [[ -f "${chart_dir}/Chart.yaml" ]]; then
            chart_name=$(basename "${chart_dir}")
            helm lint "${chart_dir}" >/dev/null
            echo -e "  [${GREEN}✓${NC}] Chart ${BOLD}${chart_name}${NC} passed helm lint"
        fi
    done
else
    echo -e "  [${YELLOW}!${NC}] Helm not installed, skipping helm lint (run ./setup.sh to install)"
fi

echo -e "${GREEN}${BOLD}==> All validation checks passed successfully!${NC}\n"
