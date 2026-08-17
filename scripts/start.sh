#!/usr/bin/env bash
# ==============================================================================
# scripts/start.sh - One-Command Launcher for Taiflix Servarr Stack
# ==============================================================================
set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/bin:${PATH}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}            Starting Taiflix Servarr Stack            ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}\n"

# 1. Probe hardware & generate secrets
echo -e "${CYAN}${BOLD}[1/5] Probing hardware & preparing secrets...${NC}"
./scripts/detect-hardware.sh
./scripts/generate-secrets.sh

# 2. Check cluster connectivity or suggest k3d/kind
echo -e "\n${CYAN}${BOLD}[2/5] Checking Kubernetes Cluster Connection...${NC}"
HAS_K8S="false"
if command -v kubectl >/dev/null 2>&1; then
    if kubectl cluster-info >/dev/null 2>&1; then
        HAS_K8S="true"
        CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "default")
        echo -e "  [${GREEN}✓${NC}] Connected to Kubernetes cluster: ${BOLD}${CURRENT_CTX}${NC}"
    fi
fi

if [[ "${HAS_K8S}" == "false" ]]; then
    echo -e "  [${YELLOW}!${NC}] No active Kubernetes cluster detected."

    # Check if k3d or kind can be created
    if command -v k3d >/dev/null 2>&1; then
        echo -e "  Found ${BOLD}k3d${NC}. Creating local development cluster 'taiflix'..."
        k3d cluster create taiflix \
            --port "80:80@loadbalancer" \
            --port "443:443@loadbalancer" \
            --volume "/media:/media" \
            --k3s-arg "--disable=traefik@server:0" || true
        HAS_K8S="true"
    elif command -v kind >/dev/null 2>&1; then
        echo -e "  Found ${BOLD}kind${NC}. Creating local development cluster 'taiflix'..."
        kind create cluster --name taiflix || true
        HAS_K8S="true"
    else
        echo -e "  ${YELLOW}Tip: To run a local cluster, you can install k3d or kind:${NC}"
        echo -e "       sudo pacman -S --needed kubectl helm k3d (on Arch/CachyOS)"
        echo -e "       or brew install kubectl helm k3d"
    fi
fi

# 3. Apply Secret to Kubernetes
if [[ "${HAS_K8S}" == "true" ]]; then
    echo -e "\n${CYAN}${BOLD}[3/5] Deploying namespace and secrets to cluster...${NC}"
    kubectl create namespace media --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/values/servarr-secrets.generated.yaml" -n media
    echo -e "  [${GREEN}✓${NC}] Applied ${BOLD}servarr-secrets${NC} into namespace ${BOLD}media${NC}."

    # 4. Check ArgoCD or Direct Helm Deploy
    echo -e "\n${CYAN}${BOLD}[4/5] Deploying Applications...${NC}"
    if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
        echo -e "  [${GREEN}✓${NC}] Detected ArgoCD! Applying root application..."
        kubectl apply -f "${SCRIPT_DIR}/argocd/root-app.yaml"
        echo -e "  [${GREEN}✓${NC}] ArgoCD Root App applied."
    elif command -v helm >/dev/null 2>&1; then
        echo -e "  [${CYAN}i${NC}] ArgoCD CRD not detected. Deploying charts directly via Helm..."

        # Deploy base infra and services
        helm upgrade --install flaresolverr "${SCRIPT_DIR}/charts/flaresolverr" -n media
        helm upgrade --install qbittorrent "${SCRIPT_DIR}/charts/qbittorrent" -f "${SCRIPT_DIR}/values/values-global.yaml" -n media

        # Deploy *arr apps using servarr-app chart
        for app in prowlarr sonarr radarr lidarr bazarr; do
            PORT=8989
            [[ "$app" == "prowlarr" ]] && PORT=9696
            [[ "$app" == "radarr" ]] && PORT=7878
            [[ "$app" == "lidarr" ]] && PORT=8686
            [[ "$app" == "bazarr" ]] && PORT=6767

            helm upgrade --install "$app" "${SCRIPT_DIR}/charts/servarr-app" \
                --set appName="$app" \
                --set image.repository="lscr.io/linuxserver/$app" \
                --set service.port="$PORT" \
                --set secretKeyRef.apiKeyEnvVar="$(echo "${app}_API_KEY" | tr '[:lower:]' '[:upper:]')" \
                --set initSeedConfig.port="$PORT" \
                --set initSeedConfig.authMethod="None" \
                --set initSeedConfig.authRequired="DisabledForLocalAddresses" \
                --set ingress.host="${app}.taiflix.lan" \
                -f "${SCRIPT_DIR}/values/values-global.yaml" \
                -n media
        done

        helm upgrade --install jellyfin "${SCRIPT_DIR}/charts/jellyfin" -f "${SCRIPT_DIR}/values/values-global.yaml" -f "${SCRIPT_DIR}/values/hardware.yaml" -n media
        helm upgrade --install jellyseerr "${SCRIPT_DIR}/charts/jellyseerr" -n media
        helm upgrade --install configarr "${SCRIPT_DIR}/charts/configarr" -n media
        helm upgrade --install servarr-wire "${SCRIPT_DIR}/charts/servarr-wire" -n media
        echo -e "  [${GREEN}✓${NC}] All Helm charts deployed into namespace ${BOLD}media${NC}."
    else
        echo -e "  [${YELLOW}!${NC}] To complete deployment, apply via ArgoCD or install Helm."
    fi

    # 5. Display Access Dashboard
    echo -e "\n${CYAN}${BOLD}[5/5] Live Service Ingress Endpoints${NC}"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "  ${BOLD}Jellyfin (Media):${NC}    \033[4;36mhttp://jellyfin.taiflix.lan\033[0m"
    echo -e "  ${BOLD}Configarr (TRaSH Sync):${NC}\033[4;36mhttp://configarr.taiflix.lan\033[0m"
    echo -e "  ${BOLD}Jellyseerr (Requests):${NC}\033[4;36mhttp://requests.taiflix.lan\033[0m"
    echo -e "  ${BOLD}Sonarr (TV Shows):${NC}   \033[4;36mhttp://sonarr.taiflix.lan\033[0m"
    echo -e "  ${BOLD}Radarr (Movies):${NC}     \033[4;36mhttp://radarr.taiflix.lan\033[0m"
    echo -e "  ${BOLD}Lidarr (Music):${NC}      \033[4;36mhttp://lidarr.taiflix.lan\033[0m"
    echo -e "  ${BOLD}Prowlarr (Indexers):${NC} \033[4;36mhttp://prowlarr.taiflix.lan\033[0m"
    echo -e "  ${BOLD}Bazarr (Subtitles):${NC}  \033[4;36mhttp://bazarr.taiflix.lan\033[0m"
    echo -e "  ${BOLD}qBittorrent (Torrents):${NC}\033[4;36mhttp://qbittorrent.taiflix.lan\033[0m"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "  ${BOLD}Setup DNS (/etc/hosts):${NC} \033[32mmake hosts\033[0m"
    echo -e "  ${BOLD}Check Server Health:${NC}    \033[32mmake health\033[0m"
    echo -e "  ${BOLD}View Auto-Wiring Logs:${NC}  \033[32mmake logs\033[0m"
    echo -e "${BLUE}======================================================${NC}\n"
fi
