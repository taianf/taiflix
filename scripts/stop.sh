#!/usr/bin/env bash
# ==============================================================================
# scripts/stop.sh - Stop & Teardown helper for Taiflix Servarr Stack
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}==> Stopping Taiflix Servarr Stack...${NC}"

if command -v kubectl >/dev/null 2>&1; then
    if kubectl get namespace media >/dev/null 2>&1; then
        echo -e "  Deleting resources in namespace ${BOLD}media${NC}..."
        if command -v helm >/dev/null 2>&1; then
            helm uninstall prowlarr sonarr radarr lidarr bazarr jellyfin jellyseerr qbittorrent flaresolverr configarr servarr-wire -n media 2>/dev/null || true
        fi
        if kubectl get application -n argocd taiflix-root >/dev/null 2>&1; then
            kubectl delete -f argocd/root-app.yaml --ignore-not-found=true
        fi
        echo -e "  [${RED}✓${NC}] Stack stopped."
    else
        echo -e "  Namespace 'media' not found on cluster."
    fi
fi
