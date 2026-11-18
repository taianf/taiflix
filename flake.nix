{
  description = "NixOS on WSL with Nixflix Media Server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
    nixflix.url = "github:kiriwalawren/nixflix";
  };

  outputs = { self, nixpkgs, nixos-wsl, nixflix, ... }@inputs: {
    nixosConfigurations.taiflix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        # NixOS-WSL module (replaces hardware-configuration.nix and bootloader)
        nixos-wsl.nixosModules.default

        # Nixflix module
        nixflix.nixosModules.default

        # Media server stack config
        ./modules/media-server.nix

        # System / WSL configuration
        ./configuration.nix
      ];
    };
  };
}
