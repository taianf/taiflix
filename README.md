# Taiflix (NixOS on WSL + Nixflix)

This repository configures your NixOS WSL distribution with [NixOS-WSL](https://github.com/nix-community/NixOS-WSL) and the [Nixflix](https://github.com/kiriwalawren/nixflix) media server stack.

## Files

- [flake.nix](file:///d:/workspace/taiflix/flake.nix): Flake inputs (`nixpkgs`, `nixos-wsl`, and `nixflix`).
- [configuration.nix](file:///d:/workspace/taiflix/configuration.nix): WSL-specific system configuration.
- [modules/media-server.nix](file:///d:/workspace/taiflix/modules/media-server.nix): Nixflix options (Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent, Seerr, WireGuard VPN, Postgres, paths).

---

## WireGuard VPN Setup

Nixflix routes `qbittorrent` through a dedicated WireGuard network namespace with an automatic kill switch, while allowing local access from your host machine.

Place your WireGuard configuration file (e.g. from Mullvad, ProtonVPN, AirVPN) at:
```bash
sudo mkdir -p /data/.state/vpn
sudo nano /data/.state/vpn/wireguard.conf
sudo chmod 600 /data/.state/vpn/wireguard.conf
```

---

## How to Apply Inside WSL

Inside your WSL NixOS terminal:

1. **Navigate to this workspace directory**:
   ```bash
   cd /mnt/d/workspace/taiflix
   ```

2. **Verify your WSL username**:
   Check `whoami`. If it's not `nixos`, update `wsl.defaultUser` in [configuration.nix](file:///d:/workspace/taiflix/configuration.nix).

3. **Verify storage directories**:
   In [modules/media-server.nix](file:///d:/workspace/taiflix/modules/media-server.nix), make sure `mediaDir` and `stateDir` paths exist or are pointing to your preferred WSL or `/mnt/d/` paths.

4. **Rebuild the NixOS configuration**:
   ```bash
   sudo nixos-rebuild switch --flake .#taiflix
   ```

5. **Access the Web UIs from Windows**:
   WSL2 mirrors localhost to Windows by default:
   - **Jellyfin**: `http://localhost:8096`
   - **Sonarr**: `http://localhost:8989`
   - **Radarr**: `http://localhost:7878`
   - **Prowlarr**: `http://localhost:9696`
   - **qBittorrent**: `http://localhost:8080`
   - **Seerr (Jellyseerr)**: `http://localhost:5055`
