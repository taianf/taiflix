#!/usr/bin/env bash
# ==============================================================================
# scripts/status.sh - Display health & status of Taiflix Servarr stack
# ==============================================================================
set -euo pipefail

BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}             Taiflix Servarr Stack Status             ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}\n"

if command -v kubectl >/dev/null 2>&1; then
    echo -e "${CYAN}${BOLD}==> Pods in 'media' namespace:${NC}"
    kubectl get pods -n media -o wide 2>/dev/null || echo "No pods found."

    echo -e "\n${CYAN}${BOLD}==> Ingress Endpoints:${NC}"
    kubectl get ingress -n media 2>/dev/null || echo "No ingress found."

    echo -e "\n${CYAN}${BOLD}==> Auto-wiring Jobs:${NC}"
    kubectl get jobs -n media 2>/dev/null || echo "No jobs found."
else
    echo "kubectl not found. Run ./setup.sh to check tools."
fi
echo -e "\n${BLUE}${BOLD}======================================================${NC}"
