#!/usr/bin/env bash
# ==============================================================================
# scripts/port-forward.sh - Forward all Servarr Web UIs to localhost
# ==============================================================================
set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/bin:${PATH}"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}        Taiflix Local Port Forwarding Manager         ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}\n"

SERVICES=(
    "jellyfin:8096"
    "jellyseerr:5055"
    "sonarr:8989"
    "radarr:7878"
    "lidarr:8686"
    "prowlarr:9696"
    "bazarr:6767"
    "qbittorrent:8080"
)

# Kill any existing kubectl port-forward processes
pkill -f "kubectl port-forward -n media" 2>/dev/null || true

echo -e "${CYAN}Forwarding Web UI ports to localhost:${NC}"
for item in "${SERVICES[@]}"; do
    SVC="${item%%:*}"
    PORT="${item##*:}"
    kubectl port-forward -n media "svc/${SVC}" "${PORT}:${PORT}" >/dev/null 2>&1 &
    echo -e "  [${GREEN}✓${NC}] ${BOLD}${SVC}${NC} -> \033[4;36mhttp://localhost:${PORT}\033[0m"
done

echo -e "\n${BLUE}======================================================${NC}"
echo -e "  ${BOLD}All services forwarded to localhost!${NC}"
echo -e "  Press \033[1mCtrl+C\033[0m or run \033[32mmake health\033[0m to test connections."
echo -e "${BLUE}======================================================${NC}\n"

# Keep script running if called in foreground, or wait
wait
