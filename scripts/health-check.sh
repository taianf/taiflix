#!/usr/bin/env bash
# ==============================================================================
# scripts/health-check.sh - Live HTTP & Pod Health Checker for Taiflix
# ==============================================================================
set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/bin:${PATH}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}            Taiflix Server Health Dashboard           ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}\n"

# 1. Pod Status Summary
echo -e "${CYAN}${BOLD}[1/2] Kubernetes Pod Status (namespace: media):${NC}"
if command -v kubectl >/dev/null 2>&1; then
    kubectl get pods -n media -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,IP:.status.podIP" | awk 'NR==1 {print "\033[1m" $0 "\033[0m"} NR>1 {if ($3=="Running" || $3=="Succeeded") print "\033[32m" $0 "\033[0m"; else print "\033[33m" $0 "\033[0m"}'
else
    echo "kubectl not found."
fi

# 2. HTTP Endpoint Health Checks
echo -e "\n${CYAN}${BOLD}[2/2] Live Service Reachability:${NC}"

check_service() {
    local name="$1"
    local port="$2"
    local path="$3"
    local url="http://127.0.0.1:${port}${path}"

    # First check localhost
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 1 "${url}" || echo "000")

    if [[ "${status_code}" =~ ^(200|201|204|302|401|403)$ ]]; then
        echo -e "  [${GREEN}ONLINE${NC}] ${BOLD}${name}${NC} -> \033[4;36mhttp://localhost:${port}\033[0m (HTTP ${GREEN}${status_code}${NC})"
    else
        # Check pod readiness inside Kubernetes
        local pod_ready
        pod_ready=$(kubectl get pods -n media -l "app.kubernetes.io/name=${name}" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [[ "${pod_ready}" == "true" ]]; then
            echo -e "  [${GREEN}ONLINE in Cluster${NC}] ${BOLD}${name}${NC} (Pod Ready) -> Run \033[32mmake port-forward\033[0m to open locally"
        else
            echo -e "  [${YELLOW}STARTING / PULLING IMAGE${NC}] ${BOLD}${name}${NC}"
        fi
    fi
}

check_service "jellyfin"    "8096" "/health"
check_service "jellyseerr"  "5055" "/api/v1/status"
check_service "sonarr"      "8989" "/ping"
check_service "radarr"      "7878" "/ping"
check_service "lidarr"      "8686" "/ping"
check_service "prowlarr"    "9696" "/ping"
check_service "bazarr"      "6767" "/api/system/status"
check_service "qbittorrent" "8080" "/api/v2/app/version"

echo -e "\n${BLUE}======================================================${NC}"
echo -e "  ${BOLD}Port Forward to localhost:${NC} \033[32mmake port-forward\033[0m"
echo -e "  ${BOLD}View Auto-Wiring Logs:${NC}     \033[32mmake logs\033[0m"
echo -e "${BLUE}======================================================${NC}\n"
