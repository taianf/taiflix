{ config, pkgs, ... }:

{
  nixflix = {
    enable = true;

    # TRaSH Guides convention directories
    mediaDir = "/data/media";
    stateDir = "/data/.state";

    # Jellyfin Configuration
    jellyfin = {
      enable = true;
      apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinSecretApiKey123456789012";

      # Declarative Jellyfin admin user
      users.taian = {
        policy.isAdministrator = true;
        password._secret = pkgs.writeText "jellyfin-password" "admin123";
      };
    };

    # Sonarr Configuration
    sonarr = {
      enable = true;
      config = {
        apiKey._secret = pkgs.writeText "sonarr-apikey" "sonarrSecretApiKey12345678901234";
        hostConfig = {
          username = "taian";
          password._secret = pkgs.writeText "sonarr-password" "admin123";
        };
      };
    };

    # Radarr Configuration
    radarr = {
      enable = true;
      config = {
        apiKey._secret = pkgs.writeText "radarr-apikey" "radarrSecretApiKey12345678901234";
        hostConfig = {
          username = "taian";
          password._secret = pkgs.writeText "radarr-password" "admin123";
        };
      };
    };

    # Prowlarr Configuration
    prowlarr = {
      enable = true;
      config = {
        apiKey._secret = pkgs.writeText "prowlarr-apikey" "prowlarrSecretApiKey123456789012";
        hostConfig = {
          username = "taian";
          password._secret = pkgs.writeText "prowlarr-password" "admin123";
        };
      indexers = [
        { name = "YTS"; }
        { name = "The Pirate Bay"; }
        { name = "Nyaa.si"; }
        { name = "sukebei.nyaa.si"; }
        { name = "Tokyo Toshokan"; }
        { name = "Internet Archive"; }
        { name = "RuTracker.org"; }
        { name = "Zamunda LIFE"; }
        # Cloudflare-protected indexers (routed via FlareSolverr) - working subset
        { name = "BTdirectory"; tags = [ "flaresolverr" ]; }
        { name = "DaMagNet"; tags = [ "flaresolverr" ]; }
        { name = "The Pirate Bay (Flare)"; schemaName = "The Pirate Bay"; tags = [ "flaresolverr" ]; }
        { name = "Torrent[CORE]"; tags = [ "flaresolverr" ]; }
        { name = "TorrentByte"; tags = [ "flaresolverr" ]; }
        { name = "Torrenttip"; tags = [ "flaresolverr" ]; }
        { name = "Uindex"; tags = [ "flaresolverr" ]; }
        { name = "XXXClub"; tags = [ "flaresolverr" ]; }
      ];

      };
    };

    # Shared PostgreSQL backend for services
    postgres.enable = true;

    # Download Client (qBittorrent)
    torrentClients.qbittorrent = {
      enable = true;
      password = "admin123";
      vpn.enable = true;
      serverConfig.Preferences.WebUI = {
        Username = "admin";
        Password_PBKDF2 = "@ByteArray(9zgDdIGaRLTTYofBAEbmTA==:9afsurbsW4a3Tb5XzQV6BxSZ11Pa5qVCBWygqaZ3pEJ7OODNGE/YpZynUMs9u8CYiUme5x+/u+GW2vporilENQ==)";
      };
    };

# Media Request Management
    seerr = {
      enable = true;
      apiKey._secret = pkgs.writeText "seerr-apikey" "seerrSecretApiKey12345678901234";
    };

    # FlareSolverr for Cloudflare-protected indexers
    flaresolverr.enable = true;

    # WireGuard VPN Integration (routes qbittorrent through VPN with killswitch)
    vpn = {
      enable = true;
      # Point to your WireGuard .conf file (e.g. from Mullvad, ProtonVPN, AirVPN, etc.)
      wgConfFile = "/data/.state/vpn/wireguard.conf";

# Allow local access to qBittorrent Web UI from your local network / host
      allowedIngress = [
        "127.0.0.1/32"
        "192.168.0.0/16"
        "10.0.0.0/8"
        "172.16.0.0/12"
      ];
    # Optional port forwarding through VPN for active torrent seeding:
    # openVPNPorts = [
    #   { port = 51413; protocol = "both"; }
    # ];
    };
  };

  # Port-forward qBittorrent WebUI from VPN namespace to host localhost:8282
  systemd.services.qbittorrent-webui-proxy = {
    description = "Proxy qBittorrent WebUI from VPN namespace to host";
    after = [ "qbittorrent.service" "wg.service" ];
    requires = [ "qbittorrent.service" "wg.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 5;
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8282,fork,reuseaddr,bind=127.0.0.1 TCP:192.168.15.1:8282";
    };
  };
}
