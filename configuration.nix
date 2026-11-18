{ config, lib, pkgs, ... }:

{
  # WSL Settings
  wsl.enable = true;
  wsl.defaultUser = "taian";

  # Prevent systemd-tmpfiles from failing on read-only WSLg mounts (/tmp/.X11-unix)
  systemd.tmpfiles.packages = lib.mkForce [];

  # Fix for WSL: Disable strict sandbox directives that cause status=226/NAMESPACE errors
  systemd.services.seerr.serviceConfig = {
    ProtectSystem = lib.mkForce false;
    ProtectHome = lib.mkForce false;
    PrivateTmp = lib.mkForce false;
    RestrictNamespaces = lib.mkForce false;
  };

  systemd.services.jellyfin-setup-wizard.serviceConfig = {
    ProtectSystem = lib.mkForce false;
    ProtectHome = lib.mkForce false;
    PrivateTmp = lib.mkForce false;
    RestrictNamespaces = lib.mkForce false;
  };

  systemd.services.jellyfin-setup-dirs = {
    description = "Create jellyfin runtime directories";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/mkdir -p /run/jellyfin";
    };
  };

  # Make jellyfin-setup-wizard depend on our dir creation
  systemd.services.jellyfin-setup-wizard.after = lib.mkAfter [ "jellyfin-setup-dirs.service" ];
  systemd.services.jellyfin-setup-wizard.requires = lib.mkAfter [ "jellyfin-setup-dirs.service" ];

  systemd.services.jellyfin-plugins.serviceConfig = {
    ProtectSystem = lib.mkForce false;
    ProtectHome = lib.mkForce false;
    PrivateTmp = lib.mkForce false;
    RestrictNamespaces = lib.mkForce false;
  };

  systemd.services.qbittorrent.serviceConfig = {
    ProtectSystem = lib.mkForce false;
    ProtectHome = lib.mkForce false;
    PrivateDevices = lib.mkForce false;
    PrivateUsers = lib.mkForce false;
    RestrictNamespaces = lib.mkForce false;
    # Clear strict inaccessible/bind paths that fail on WSL
    InaccessiblePaths = lib.mkForce [ "-/run/nscd" "-/run/resolvconf" ];
    ProcSubset = lib.mkForce "all";
    ProtectProc = lib.mkForce "default";
  };

  networking.hostName = "taiflix";

  users.users.taian = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Essential CLI tools
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    jq
    htop
    btop
    ncdu
    tree
    fd
    ripgrep
    fzf
    bat
    eza
    zoxide
    yq
    tokei
    hyperfine
    direnv
    gnugrep
    gnutar
    gzip
    bzip2
    xz
    zip
    unzip
    p7zip
    rsync
    socat
    netcat
    nmap
    bind
    dnsutils
    iproute2
    net-tools
    htop
    iftop
    nethogs
    iotop
    sysstat
  ];

  system.stateVersion = "24.11"; # Adjust to match your installed NixOS release
}
