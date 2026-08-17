#!/usr/bin/env bash
# ==============================================================================
# scripts/create-cluster.sh - Creates a high-performance local k3d cluster
# ==============================================================================
set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/bin:${PATH}"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

CLUSTER_NAME="taiflix"

echo -e "${BLUE}${BOLD}==> Initializing local Kubernetes cluster ('${CLUSTER_NAME}')...${NC}"

# Check if k3d is installed
if ! command -v k3d >/dev/null 2>&1; then
    echo -e "  [${YELLOW}!${NC}] ${BOLD}k3d${NC} is not installed."
    echo -e "  To install k3d, run one of:"
    echo -e "    - \033[32msudo pacman -S k3d\033[0m (Arch/CachyOS)"
    echo -e "    - \033[32mbrew install k3d\033[0m"
    echo -e "    - \033[32mcurl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash\033[0m"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo -e "  \033[31m[✗] Docker daemon is not running. Please start Docker first.\033[0m"
    exit 1
fi

# Check if cluster already exists
if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
    echo -e "  [${GREEN}✓${NC}] Cluster '${CLUSTER_NAME}' already exists."
    k3d cluster start "${CLUSTER_NAME}" || true
else
    echo -e "  Creating k3d cluster '${CLUSTER_NAME}' with /media volume & port bindings..."

    # Ensure /media directory exists on host
    sudo mkdir -p /media/downloads/completed /media/downloads/incomplete /media/tv /media/movies /media/music 2>/dev/null || mkdir -p /media/downloads/completed /media/downloads/incomplete /media/tv /media/movies /media/music 2>/dev/null || true

    k3d cluster create "${CLUSTER_NAME}" \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "8080:8080@loadbalancer" \
        --port "8096:8096@loadbalancer" \
        --port "8989:8989@loadbalancer" \
        --port "7878:7878@loadbalancer" \
        --port "9696:9696@loadbalancer" \
        --port "8686:8686@loadbalancer" \
        --port "6767:6767@loadbalancer" \
        --port "5055:5055@loadbalancer" \
        --volume "/media:/media" \
        --k3s-arg "--disable=traefik@server:0"
fi

# Switch kubectl context
kubectl config use-context "k3d-${CLUSTER_NAME}"

echo -e "  [${GREEN}✓${NC}] Kubernetes cluster '${CLUSTER_NAME}' is ready!"

# ----------------------------------------------------------------------------
# Install Traefik ingress controller.
# k3s's bundled Traefik is disabled above (--disable=traefik) so our
# Ingress resources have a stable, repo-pinnable controller. Idempotent.
# ----------------------------------------------------------------------------
if ! kubectl get ns kube-system >/dev/null 2>&1; then
    echo -e "  ${YELLOW}!${NC} kube-system not reachable yet, skipping Traefik install"
else
    echo -e "  Installing Traefik ingress controller..."
    if ! helm repo list 2>/dev/null | grep -q '^traefik'; then
        helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
    fi
    helm repo update >/dev/null 2>&1 || true
    helm upgrade --install traefik traefik/traefik \
        --namespace kube-system \
        --version "37.4.0" \
        --set ingressClass.enabled=true \
        --set ingressClass.isDefaultClass=true \
        --set api.insecure=true \
        --set ports.web.port=80 \
        --set ports.websecure.port=443 \
        --wait >/dev/null 2>&1 && \
        echo -e "  [${GREEN}✓${NC}] Traefik ingress controller deployed." || \
        echo -e "  ${YELLOW}!${NC} Traefik install failed (cluster may still be starting). Re-run this script to retry."
fi
