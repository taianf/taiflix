#!/usr/bin/env bash
# ==============================================================================
# setup.sh - Environment Bootstrapper & Dependency Checker for Taiflix
# ==============================================================================
set -euo pipefail

# Ensure ~/.local/bin and common tool paths are in PATH
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/bin:${PATH}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}       Taiflix Servarr Stack - Setup & Doctor         ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}\n"

# Tracking missing tools
MISSING_TOOLS=()
OPTIONAL_MISSING_TOOLS=()

check_command() {
    local cmd="$1"
    local desc="$2"
    local required="$3" # "true" or "false"

    if command -v "${cmd}" >/dev/null 2>&1; then
        local version_str
        version_str=$("${cmd}" --version 2>&1 | head -n 1 || echo "installed")
        echo -e "  [${GREEN}✓${NC}] ${BOLD}${cmd}${NC} (${desc}) - ${CYAN}${version_str}${NC}"
        return 0
    else
        if [[ "${required}" == "true" ]]; then
            echo -e "  [${RED}✗${NC}] ${BOLD}${cmd}${NC} (${desc}) - ${RED}NOT FOUND (Required)${NC}"
            MISSING_TOOLS+=("${cmd}")
        else
            echo -e "  [${YELLOW}!${NC}] ${BOLD}${cmd}${NC} (${desc}) - ${YELLOW}NOT FOUND (Optional)${NC}"
            OPTIONAL_MISSING_TOOLS+=("${cmd}")
        fi
        return 0
    fi
}

echo -e "${CYAN}${BOLD}[1/4] Checking core system dependencies...${NC}"
check_command "git" "Version control" "true"
check_command "python3" "Scripting & auto-wiring engine" "true"
check_command "jq" "JSON processor" "true"
check_command "curl" "HTTP client for API interactions" "true"
check_command "make" "Build & automation tool" "false"

echo -e "\n${CYAN}${BOLD}[2/4] Checking Kubernetes & GitOps tools...${NC}"
check_command "kubectl" "Kubernetes CLI" "false"
check_command "helm" "Kubernetes Package Manager" "false"
check_command "kustomize" "Kubernetes Kustomization tool" "false"
check_command "kubeconform" "Fast Kubernetes manifest validator" "false"
check_command "yq" "YAML processor" "false"

echo -e "\n${CYAN}${BOLD}[3/4] Checking linters & pre-commit quality tools...${NC}"
check_command "pre-commit" "Pre-commit git hooks framework" "false"
check_command "yamllint" "YAML linter" "false"
check_command "ruff" "Python linter & formatter" "false"
check_command "shellcheck" "Shell script linter" "false"
check_command "shfmt" "Shell script formatter" "false"

echo -e "\n${CYAN}${BOLD}[4/4] Probing GPU / Hardware acceleration devices...${NC}"
if [[ -x "${SCRIPT_DIR}/scripts/detect-hardware.sh" ]]; then
    "${SCRIPT_DIR}/scripts/detect-hardware.sh" || true
else
    echo -e "  Hardware detector will be run after repository setup."
fi

# Detect package manager for installation suggestions
detect_package_manager() {
    if command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        echo "unknown"
    fi
}

PKG_MGR=$(detect_package_manager)

install_dependencies() {
    echo -e "\n${BLUE}${BOLD}Attempting to install missing development dependencies...${NC}"

    # Install python based tools via uv, pipx, or pip
    if ! command -v pre-commit >/dev/null 2>&1 || ! command -v yamllint >/dev/null 2>&1; then
        echo -e "${CYAN}Installing pre-commit, yamllint, ruff via uv/pip...${NC}"
        if command -v uv >/dev/null 2>&1; then
            uv tool install pre-commit || true
            uv tool install yamllint || true
            uv tool install ruff || true
        elif command -v pipx >/dev/null 2>&1; then
            pipx install pre-commit || true
            pipx install yamllint || true
            pipx install ruff || true
        elif command -v pip3 >/dev/null 2>&1; then
            pip3 install --user pre-commit yamllint ruff || true
        fi
    fi

    # Install system tools via package manager if available
    case "${PKG_MGR}" in
        pacman)
            echo -e "${CYAN}Detected Arch Linux / CachyOS (pacman).${NC}"
            local to_install=()
            for tool in kubectl helm kustomize shellcheck shfmt yq kubeconform; do
                if ! command -v "${tool}" >/dev/null 2>&1; then
                    to_install+=("${tool}")
                fi
            done
            if [[ ${#to_install[@]} -gt 0 ]]; then
                echo -e "${YELLOW}Suggested command to install missing tools:${NC}"
                echo -e "  sudo pacman -S --needed ${to_install[*]}"
                if [[ "${AUTO_INSTALL:-false}" == "true" ]] || [[ "${1:-}" == "--install" ]]; then
                    sudo pacman -S --needed --noconfirm "${to_install[@]}" || true
                fi
            fi
            ;;
        brew)
            echo -e "${CYAN}Detected Homebrew.${NC}"
            local to_install=()
            for tool in kubectl helm kustomize shellcheck shfmt yq kubeconform pre-commit yamllint; do
                if ! command -v "${tool}" >/dev/null 2>&1; then
                    to_install+=("${tool}")
                fi
            done
            if [[ ${#to_install[@]} -gt 0 ]]; then
                if [[ "${AUTO_INSTALL:-false}" == "true" ]] || [[ "${1:-}" == "--install" ]]; then
                    brew install "${to_install[@]}" || true
                else
                    echo -e "${YELLOW}Suggested command to install missing tools:${NC}"
                    echo -e "  brew install ${to_install[*]}"
                fi
            fi
            ;;
        apt)
            echo -e "${CYAN}Detected Debian/Ubuntu (apt).${NC}"
            echo -e "${YELLOW}Suggested commands:${NC}"
            echo -e "  sudo apt-get update && sudo apt-get install -y git jq curl make shellcheck yamllint"
            ;;
        *)
            echo -e "${YELLOW}Manual installation needed for missing packages on this system.${NC}"
            ;;
    esac
}

# Auto install if flag provided
if [[ "${1:-}" == "--install" ]]; then
    install_dependencies "--install"
fi

# Setup Git Hooks if pre-commit is available
if command -v pre-commit >/dev/null 2>&1; then
    echo -e "\n${CYAN}${BOLD}Configuring Git pre-commit hooks...${NC}"
    if [[ -f "${SCRIPT_DIR}/.pre-commit-config.yaml" ]]; then
        pre-commit install || true
        echo -e "  [${GREEN}✓${NC}] Pre-commit hooks installed successfully."
    fi
elif command -v prek >/dev/null 2>&1; then
    echo -e "\n${CYAN}${BOLD}Configuring Git prek hooks...${NC}"
    prek install || true
fi

# Initialize secret file template if missing
if [[ ! -f "${SCRIPT_DIR}/values/values-secret.yaml" ]] && [[ -f "${SCRIPT_DIR}/values/values-secret.example.yaml" ]]; then
    echo -e "\n${CYAN}${BOLD}Initializing values-secret.yaml template...${NC}"
    cp "${SCRIPT_DIR}/values/values-secret.example.yaml" "${SCRIPT_DIR}/values/values-secret.yaml"
    echo -e "  [${GREEN}✓${NC}] Created ${BOLD}values/values-secret.yaml${NC} (Fill in your ADMIN_PASSWORD)."
fi

# Generate derived secrets if script exists
if [[ -x "${SCRIPT_DIR}/scripts/generate-secrets.sh" ]]; then
    "${SCRIPT_DIR}/scripts/generate-secrets.sh"
fi

echo -e "\n${BLUE}${BOLD}======================================================${NC}"
if [[ ${#MISSING_TOOLS[@]} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD} All core requirements are met! Ready to develop.${NC}"
else
    echo -e "${YELLOW}${BOLD} Some required dependencies are missing: ${MISSING_TOOLS[*]}${NC}"
    echo -e " Run ${BOLD}./setup.sh --install${NC} or install them via your package manager."
fi
echo -e "${BLUE}${BOLD}======================================================${NC}\n"
