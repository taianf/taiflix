#!/usr/bin/env bash
# ==============================================================================
# scripts/detect-hardware.sh - Probes system GPU & generates values/hardware.yaml
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/values/hardware.yaml"

echo -e "\033[1;34m==>\033[0m \033[1mProbing host hardware for video transcoding acceleration...\033[0m"

HAS_NVIDIA="false"
HAS_INTEL_QSV="false"
NVIDIA_MODEL=""
INTEL_MODEL=""

# 1. Check for NVIDIA GPU
if command -v nvidia-smi >/dev/null 2>&1; then
    NVIDIA_OUT=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true)
    if [[ -n "${NVIDIA_OUT}" ]]; then
        HAS_NVIDIA="true"
        NVIDIA_MODEL="${NVIDIA_OUT}"
        echo -e "  \033[32m[✓]\033[0m Found NVIDIA GPU: \033[1m${NVIDIA_MODEL}\033[0m"
    fi
elif ls -d /dev/nvidia* >/dev/null 2>&1; then
    HAS_NVIDIA="true"
    NVIDIA_MODEL="NVIDIA Device (/dev/nvidia*)"
    echo -e "  \033[32m[✓]\033[0m Found NVIDIA device node in /dev/nvidia*"
fi

# 2. Check for Intel GPU / QuickSync (renderD128)
if [[ -e "/dev/dri/renderD128" ]] || [[ -d "/dev/dri" ]]; then
    INTEL_VGA=$(lspci 2>/dev/null | grep -i "VGA.*Intel" || true)
    if [[ -n "${INTEL_VGA}" ]] || [[ -e "/dev/dri/renderD128" ]]; then
        HAS_INTEL_QSV="true"
        INTEL_MODEL="${INTEL_VGA:-Intel Integrated Graphics (/dev/dri/renderD128)}"
        echo -e "  \033[32m[✓]\033[0m Found Intel QuickSync / VAAPI: \033[1m${INTEL_MODEL}\033[0m"
    fi
fi

# Determine optimal mode
RECOMMENDED_MODE="cpu"
if [[ "${HAS_NVIDIA}" == "true" ]]; then
    RECOMMENDED_MODE="nvidia"
elif [[ "${HAS_INTEL_QSV}" == "true" ]]; then
    RECOMMENDED_MODE="qsv"
fi

echo -e "  \033[36mOptimal Transcoding Mode:\033[0m \033[1m${RECOMMENDED_MODE}\033[0m"

# Ensure output directory exists
mkdir -p "${SCRIPT_DIR}/values"

# Generate values/hardware.yaml
cat <<EOF > "${OUTPUT_FILE}"
# ==============================================================================
# values/hardware.yaml - Auto-generated Hardware Acceleration Configuration
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================================

hardware:
  # Mode options: 'auto', 'nvidia', 'qsv' (Intel QuickSync), 'vaapi', 'cpu'
  transcodingMode: "${RECOMMENDED_MODE}"

  nvidia:
    enabled: $(if [[ "${HAS_NVIDIA}" == "true" ]]; then echo "true"; else echo "false"; fi)
    runtimeClassName: "nvidia" # standard for nvidia container toolkit
    gpuResource: "nvidia.com/gpu: 1"
    model: "${NVIDIA_MODEL}"

  intel:
    enabled: $(if [[ "${HAS_INTEL_QSV}" == "true" ]]; then echo "true"; else echo "false"; fi)
    devicePath: "/dev/dri/renderD128"
    model: "${INTEL_MODEL}"

  # Fallback to software decoding/encoding if hardware fails
  allowFallbackToCpu: true
EOF

echo -e "\033[32m  [✓] Updated ${OUTPUT_FILE}\033[0m\n"
