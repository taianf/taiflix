# 🎬 Taiflix - Auto-Wired Servarr Media Stack on Kubernetes

> Production-grade GitOps repository for a fully auto-wired **Servarr Media Stack** running on **Kubernetes** with **ArgoCD**, hardware transcoding auto-detection (**Intel QuickSync** / **NVIDIA NVENC**), atomic hardlinks, pre-commit validation, and single-secret management.

---

## 🌟 Key Features

- **⚡ Zero-Race Auto-Wiring**:
  - **Pre-Init**: Deterministic API keys are derived from your master password and injected into `/config/config.xml` before pods boot.
  - **PostSync Orchestrator (`servarr-wire`)**: An automated ArgoCD PostSync Job configures cross-service integrations via REST APIs:
    - Links **Prowlarr** to **Flaresolverr**, **Sonarr**, **Radarr**, **Lidarr**, and **qBittorrent**.
    - Links **Sonarr / Radarr / Lidarr** to **qBittorrent** download client and sets root folders (`/media/*`).
    - Links **Bazarr** subtitle management to **Sonarr** and **Radarr**.
    - Links **Jellyseerr** media discovery to **Jellyfin**, **Sonarr**, and **Radarr**.
- **🚀 Dual Hardware Transcoding Auto-Detection**:
  - Automatically probes host devices for **NVIDIA GPUs** (NVENC/NVDEC) and **Intel QuickSync** (`/dev/dri/renderD128`).
  - Automatically seeds Jellyfin's `encoding.xml` with optimal hardware decoder/encoder and tone mapping parameters.
- **🔒 Single-Secret Simplicity**:
  - You only provide **`ADMIN_PASSWORD`** in `values/values-secret.yaml` (ignored in Git).
  - All internal API keys, tokens, and WebUI credentials are automatically generated and populated into a single Kubernetes Secret.
- **💾 Atomic 0-Copy Hardlinks**:
  - Unified `/media` volume structure across all download and media containers ensures instant, zero-duplicate-disk file moves between torrent downloads and media libraries.
- **✨ Quality & Format Automation**:
  - **[Configarr](https://configarr.de/)** automatically syncs [TRaSH Guides](https://trash-guides.info/) recommended quality profiles, naming formats, and custom formats across Sonarr, Radarr, and Lidarr.
- **🛡️ Pre-commit (prek) Quality Checks**:
  - Full validation suite: `yamllint`, `helm lint`, `kubeconform`, `shellcheck`, `shfmt`, `ruff`, and Git security checks.

---

## 🏗️ Architecture & Topology

```mermaid
graph TD
    subgraph GitOps [ArgoCD Control Plane]
        RootApp[ArgoCD Root App / App of Apps]
    end

    subgraph HardwareLayer [Hardware & Transcoding Detection]
        HWDetect["Hardware Probe (scripts/detect-hardware.sh + InitContainer)"]
        HWDetect --> |Detects NVIDIA /dev/nvidia*| NVENC[NVIDIA NVENC/NVDEC]
        HWDetect --> |Detects Intel /dev/dri| QSV[Intel QuickSync / QSV]
        NVENC --> JellyfinConfig["Jellyfin Auto-Config (encoding.xml)"]
        QSV --> JellyfinConfig
    end

    subgraph SecretsManagement [Secret Derivation]
        MasterSecret["values-secret.yaml (ADMIN_PASSWORD)"] --> K8sSecret["K8s Secret: servarr-secrets (API keys + hashes)"]
    end

    subgraph ServarrApps [Servarr Applications]
        Prowlarr[Prowlarr (Indexers)]
        Flaresolverr[Flaresolverr (CF Bypass)]
        qBittorrent[qBittorrent + Gluetun VPN]
        Sonarr[Sonarr (TV Shows)]
        Radarr[Radarr (Movies)]
        Lidarr[Lidarr (Music)]
        Bazarr[Bazarr (Subtitles)]
        Jellyfin[Jellyfin (Media Server - Auto HW Acceleration)]
        Jellyseerr[Jellyseerr (Media Requests)]
        Configarr[Configarr (TRaSH Guides)]
    end

    subgraph Orchestration [Auto-Wiring Engine]
        PreInit["InitContainers: Pre-seed config.xml with deterministic API keys"]
        PostSync["ArgoCD PostSync Job: servarr-wire (REST API configuration)"]
    end

    subgraph SharedStorage [Storage Mounts]
        MediaPVC["/media (HostPath / Shared NFS: atomic hardlinks)"]
        MediaPVC --> |tv| Sonarr
        MediaPVC --> |movies| Radarr
        MediaPVC --> |music| Lidarr
        MediaPVC --> |downloads| qBittorrent
        MediaPVC --> |media| Jellyfin
        ConfigPVCs["Config PVCs (SQLite / AppData per service)"]
    end

    RootApp --> ServarrApps
    PreInit --> ServarrApps
    JellyfinConfig --> Jellyfin
    PostSync -.-> |Configures APIs| Prowlarr
    PostSync -.-> |Configures APIs| Sonarr
    PostSync -.-> |Configures APIs| Radarr
    PostSync -.-> |Configures APIs| Lidarr
    PostSync -.-> |Configures APIs| Bazarr
    PostSync -.-> |Configures APIs| Jellyseerr
```

---

## 📦 Stack Components

| Service | Port | Ingress Host | Description |
| :--- | :--- | :--- | :--- |
| **qBittorrent** | `8080` / `6881` | `qbittorrent.taiflix.lan` | Torrent download client (optional Gluetun VPN sidecar) |
| **Prowlarr** | `9696` | `prowlarr.taiflix.lan` | Torrent indexer & Usenet proxy manager |
| **Flaresolverr** | `8191` | *Internal DNS* | Cloudflare clearance bypass proxy for indexers |
| **Sonarr** | `8989` | `sonarr.taiflix.lan` | TV Series management and auto-downloader |
| **Radarr** | `7878` | `radarr.taiflix.lan` | Movie collection manager and auto-downloader |
| **Lidarr** | `8686` | `lidarr.taiflix.lan` | Music collection manager and auto-downloader |
| **Bazarr** | `6767` | `bazarr.taiflix.lan` | Automatic subtitle finder and synchronization |
| **Jellyfin** | `8096` | `jellyfin.taiflix.lan` | Media streaming server with Intel QSV / NVIDIA NVENC |
| **Jellyseerr** | `5055` | `requests.taiflix.lan` | Modern media discovery and request management UI |
| **Configarr** | *Cron* | *None* | TRaSH Guides quality & format synchronizer (Sonarr, Radarr, Lidarr) |
| **servarr-wire**| *Job* | *None* | ArgoCD PostSync REST API cross-wiring orchestrator |

---

## 🚀 Quick Start & Deployment

### 1. Check & Install Dependencies

Run the doctor script to verify and install all necessary CLI tools:

```bash
# Check dependencies and hardware
./setup.sh

# Or install missing dependencies automatically
./setup.sh --install
```

### 2. Configure Your Admin Password & Secrets

1. Copy the example secret file:
   ```bash
   cp values/values-secret.example.yaml values/values-secret.yaml
   ```
2. Edit `values/values-secret.yaml` and set your desired `ADMIN_PASSWORD`.
3. Generate the derived Kubernetes secret:
   ```bash
   make secrets
   ```
   This derives deterministic 32-character API keys and generates `values/servarr-secrets.generated.yaml`.

### 3. Detect Hardware Acceleration

Probe your cluster node for Intel QuickSync or NVIDIA GPUs:

```bash
make detect-hw
```
This updates `values/hardware.yaml` with the optimal hardware transcoding profile.

### 4. Deploy to Kubernetes with ArgoCD

1. Apply the generated secrets to your Kubernetes cluster:
   ```bash
   kubectl create namespace media --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f values/servarr-secrets.generated.yaml -n media
   ```

2. Point `argocd/root-app.yaml` to your Git repository URL, then apply the root application:
   ```bash
   kubectl apply -f argocd/root-app.yaml
   ```

ArgoCD will automatically synchronize all services in sequence and run the `servarr-wire` PostSync Job to link everything together!

---

## 🛠️ Development & Quality Checks (`prek`)

This repository is equipped with a complete pre-commit suite. Run linting and validations anytime with:

```bash
# Run pre-commit checks on all files
make lint

# Run template and script tests
make test
```

### Makefile Reference

| Target | Description |
| :--- | :--- |
| `make setup` | Run environment setup and dependency verification |
| `make detect-hw` | Probe host/node for Intel QuickSync and NVIDIA GPU |
| `make secrets` | Generate Kubernetes secret (`servarr-secrets`) from master password |
| `make lint` | Run pre-commit hooks across all files |
| `make test` | Run syntax validation and Helm chart tests |
| `make bootstrap` | Prepare secrets and print deployment instructions |

---

## 📂 Storage & Hardlink Directory Structure

For 0-copy atomic hardlinks to work, your shared host/NFS media mount should have the following structure:

```text
/media/
├── downloads/
│   ├── completed/
│   │   ├── tv-sonarr/
│   │   ├── radarr/
│   │   └── lidarr/
│   └── incomplete/
├── movies/
├── tv/
└── music/
```

All services mount `/media` at the exact same internal mount path, enabling qBittorrent and Sonarr/Radarr to create instantaneous hardlinks without duplicating disk usage.

---

## 📄 License

MIT License. Designed with ❤️ for clean, automated home-lab GitOps.
