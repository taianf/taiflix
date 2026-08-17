# Servarr Stack Implementation Plan (Taiflix)

## 1. Overview & Architecture

This project provides a complete, production-ready GitOps repository for a fully auto-wired **Servarr Media Stack** running on **Kubernetes**, managed via **ArgoCD**, with **pre-commit (prek)** quality checks, single-secret configuration (`ADMIN_PASSWORD`), and **automatic hardware transcoding detection** (Intel QuickSync & NVIDIA NVENC).

### High-Level Topology

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
        Recyclarr[Recyclarr / Configarr (TRaSH Guides)]
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

## 2. Directory Structure

```text
taiflix/
├── PLAN.md                          # This architecture & implementation plan
├── .pre-commit-config.yaml          # Pre-commit (prek) hooks: yamllint, shellcheck, kubeconform, helm-lint
├── .gitignore                       # Ignores sensitive values-secret.yaml, logs, local caches
├── Makefile                         # Dev shortcuts: make lint, make bootstrap, make secrets, make test, make detect-hw
├── README.md                        # Complete documentation & quick-start guide
├── scripts/
│   ├── detect-hardware.sh           # Auto-detects Intel QSV (/dev/dri) & NVIDIA GPU (nvidia-smi)
│   ├── generate-secrets.sh          # Derives deterministic API keys from ADMIN_PASSWORD into K8s secret
│   ├── wire-services.py             # Auto-wiring script for PostSync Job (REST API orchestrator)
│   └── test-manifests.sh            # Local validation script (helm lint, kubeconform dry-run)
├── argocd/
│   ├── root-app.yaml                # ArgoCD App-of-Apps master Application manifest
│   ├── kustomization.yaml           # Root kustomize if managing apps via kustomize/argo
│   └── apps/                        # ArgoCD Application manifests for each service
│       ├── qbittorrent.yaml
│       ├── prowlarr.yaml
│       ├── flaresolverr.yaml
│       ├── sonarr.yaml
│       ├── radarr.yaml
│       ├── lidarr.yaml
│       ├── bazarr.yaml
│       ├── jellyfin.yaml
│       ├── jellyseerr.yaml
│       ├── configarr.yaml
│       └── servarr-wire.yaml        # PostSync auto-wiring Job
├── charts/                          # Modular Helm charts / values for each component
│   ├── shared/                      # Shared Helm templates / common library helpers
│   ├── servarr-app/                 # Generic reusable chart for *arr apps with pre-init config.xml injection
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── ingress.yaml
│   │       ├── pvc.yaml
│   │       └── init-configmap.yaml
│   ├── qbittorrent/                 # qBittorrent + optional Gluetun VPN sidecar
│   ├── jellyfin/                    # Jellyfin with auto-detecting HW acceleration (NVIDIA / Intel QSV / CPU)
│   ├── jellyseerr/                  # Jellyseerr request UI
│   ├── configarr/                   # Configarr CronJob for TRaSH guides (Sonarr/Radarr/Lidarr)
│   └── servarr-wire/                # Auto-wiring orchestrator Job definition
└── values/                          # Global and per-environment values
    ├── values-global.yaml           # Shared domain, storage paths, timezone, PUID/PGID, hardware acceleration
    ├── values-secret.example.yaml   # Template containing only ADMIN_PASSWORD
    └── environments/
        └── production.yaml          # Production environment overlay
```

---

## 3. Hardware Auto-Detection & Jellyfin Transcoding Engine

### A. Dual-Tier Auto-Detection
1. **Cluster / Node Detection (`scripts/detect-hardware.sh` / `make detect-hw`)**:
   - Inspects host/node devices:
     * Checks `/dev/dri/renderD128` (Intel QuickSync Video / VAAPI).
     * Checks `nvidia-smi` / `/dev/nvidia*` (NVIDIA RTX/GTX GPUs with NVENC/NVDEC).
   - Generates or updates `values/hardware.yaml` with the optimal hardware acceleration flags (`auto`, `nvidia`, `qsv`, `vaapi`, or `cpu`).
2. **In-Pod Dynamic Detection (`jellyfin` initContainer / startup)**:
   - Mounts both `/dev/dri` and NVIDIA runtime resources when available.
   - On pod startup, the init script inspects runtime device nodes inside the container:
     * If NVIDIA GPU is detected (`/dev/nvidia0` or `nvidia-smi` available): Pre-seeds Jellyfin's `encoding.xml` with **NVENC** hardware acceleration, enabling NVDEC for H.264, HEVC, VP9, AV1, and hardware tone mapping.
     * Else if Intel GPU is detected (`/dev/dri/renderD128`): Pre-seeds Jellyfin's `encoding.xml` with **Intel QuickSync (QSV)** or **VAAPI**, enabling Low-Power encoding, VPP tone mapping, and Intel QSV decoders.
     * Fallback: CPU/Software encoding if no acceleration device is present.
   - The auto-wiring orchestrator (`wire-services.py`) queries Jellyfin's `/System/Configuration/encoding` API to verify active transcoding configuration.

---

## 4. Pre-Init, Post-Init & Auto-Wiring Engine

### A. Secret Generation (`ADMIN_PASSWORD`)
- Master secret file `values/values-secret.yaml` (ignored by Git) contains only `ADMIN_PASSWORD`.
- `scripts/generate-secrets.sh` derives deterministic API keys and hashes for all services and writes them into `servarr-secrets`.

### B. Pre-Init: Deterministic `config.xml` Injection
- Every *arr service (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr) uses an `initContainer` to seed `/config/config.xml` with its predefined API key and authentication before launch.

### C. Post-Init Orchestration (`servarr-wire`)
An ArgoCD `PostSync` Job runs `scripts/wire-services.py`:
1. Waits for all services to become healthy.
2. Configures **qBittorrent**: auth, paths (`/media/downloads/*`), categories (`tv-sonarr`, `radarr`, `lidarr`).
3. Configures **Prowlarr**: Flaresolverr proxy, registers Sonarr/Radarr/Lidarr, sets up qBittorrent download client.
4. Configures **Sonarr / Radarr / Lidarr**: connects qBittorrent, sets root folders (`/media/tv`, `/media/movies`, `/media/music`), configures naming conventions, links Bazarr.
5. Configures **Jellyseerr**: links to Jellyfin, Sonarr, and Radarr.
6. Configures **Recyclarr**: TRaSH Guides quality profiles and custom formats sync.

---

## 5. Storage Architecture (Hardlinks)
- Unified `/media` volume structure across all pods ensures atomic hardlinks:
  - `/media/tv`
  - `/media/movies`
  - `/media/music`
  - `/media/downloads/incomplete`
  - `/media/downloads/completed`

---

## 6. Pre-commit (prek) & Quality Checks
- `.pre-commit-config.yaml` with:
  - `yamllint`, `check-yaml`, `helm-lint`, `kubeconform`, `shellcheck`, `shfmt`, `ruff`, `detect-private-key`, `trailing-whitespace`, `end-of-file-fixer`.
- `Makefile` with targets: `lint`, `detect-hw`, `secrets`, `test`, `bootstrap`.
