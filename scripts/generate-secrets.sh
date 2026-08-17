#!/usr/bin/env bash
# ==============================================================================
# scripts/generate-secrets.sh - Generates Kubernetes secret from ADMIN_PASSWORD
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_VALUES="${SCRIPT_DIR}/values/values-secret.yaml"
EXAMPLE_SECRET_VALUES="${SCRIPT_DIR}/values/values-secret.example.yaml"
OUTPUT_SECRET="${SCRIPT_DIR}/values/servarr-secrets.generated.yaml"

echo -e "\033[1;34m==>\033[0m \033[1mGenerating Servarr secrets...\033[0m"

# Ensure values-secret.yaml exists
if [[ ! -f "${SECRET_VALUES}" ]]; then
    if [[ -f "${EXAMPLE_SECRET_VALUES}" ]]; then
        echo -e "  \033[33mvalues-secret.yaml not found. Copying from values-secret.example.yaml...\033[0m"
        cp "${EXAMPLE_SECRET_VALUES}" "${SECRET_VALUES}"
    else
        cat <<EOF > "${SECRET_VALUES}"
# Taiflix Master Secret Configuration
# DO NOT COMMIT THIS FILE TO GIT
ADMIN_PASSWORD: "change_me_super_secret_admin_password_123"
EOF
    fi
fi

# Extract ADMIN_PASSWORD
ADMIN_PASSWORD=$(grep -E "^ADMIN_PASSWORD:" "${SECRET_VALUES}" | awk -F': ' '{print $2}' | tr -d '"'\'' ' || true)

if [[ -z "${ADMIN_PASSWORD}" ]] || [[ "${ADMIN_PASSWORD}" == "change_me_super_secret_admin_password_123" ]]; then
    echo -e "  \033[33m[!] Warning: Using default ADMIN_PASSWORD from template.\033[0m"
    echo -e "      You can customize it in: \033[1m${SECRET_VALUES}\033[0m"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-change_me_super_secret_admin_password_123}"
fi

# Derive deterministic API keys and hashes using python3 hashlib
python3 - <<EOF
import hashlib
import hmac
import base64
import os

admin_pw = """${ADMIN_PASSWORD}"""

def derive_api_key(service_name: str) -> str:
    # Deterministic 32-char hex string derived from ADMIN_PASSWORD + service salt
    h = hmac.new(admin_pw.encode('utf-8'), service_name.encode('utf-8'), hashlib.sha256).hexdigest()
    return h[:32]

services = ["prowlarr", "sonarr", "radarr", "lidarr", "bazarr", "jellyseerr", "jellyfin", "qbittorrent"]
keys = {svc: derive_api_key(svc) for svc in services}

# Generate qBittorrent PBKDF2 hash
# Format: @ByteArray(salt:hash) or standard pbkdf2
salt = os.urandom(16)
key = hashlib.pbkdf2_hmac('sha512', admin_pw.encode('utf-8'), salt, 100000)
qb_hash = f"@ByteArray({base64.b64encode(salt).decode('ascii')}:{base64.b64encode(key).decode('ascii')})"

secret_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: servarr-secrets
  namespace: media
  labels:
    app.kubernetes.io/part-of: taiflix
type: Opaque
stringData:
  ADMIN_PASSWORD: "{admin_pw}"
  PROWLARR_API_KEY: "{keys['prowlarr']}"
  SONARR_API_KEY: "{keys['sonarr']}"
  RADARR_API_KEY: "{keys['radarr']}"
  LIDARR_API_KEY: "{keys['lidarr']}"
  BAZARR_API_KEY: "{keys['bazarr']}"
  JELLYSEERR_API_KEY: "{keys['jellyseerr']}"
  JELLYFIN_ADMIN_PASSWORD: "{admin_pw}"
  QBITTORRENT_ADMIN_PASSWORD: "{admin_pw}"
  QBITTORRENT_PBKDF2_HASH: "{qb_hash}"
"""

with open("${OUTPUT_SECRET}", "w") as f:
    f.write(secret_yaml)

print(f"  \033[32m[✓]\033[0m Successfully derived API keys and generated Kubernetes secret:")
print(f"      - Prowlarr API Key:  {keys['prowlarr'][:6]}...{keys['prowlarr'][-4:]}")
print(f"      - Sonarr API Key:    {keys['sonarr'][:6]}...{keys['sonarr'][-4:]}")
print(f"      - Radarr API Key:    {keys['radarr'][:6]}...{keys['radarr'][-4:]}")
print(f"      - Lidarr API Key:    {keys['lidarr'][:6]}...{keys['lidarr'][-4:]}")
print(f"      - Bazarr API Key:    {keys['bazarr'][:6]}...{keys['bazarr'][-4:]}")
print(f"      - Jellyseerr API Key:{keys['jellyseerr'][:6]}...{keys['jellyseerr'][-4:]}")
print(f"  \033[32m[✓]\033[0m Saved to: \033[1m${OUTPUT_SECRET}\033[0m\n")
EOF
