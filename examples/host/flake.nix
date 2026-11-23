{
  description = "NixOS on the ACEMAGIC Matrix Mini M1 with Orca";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-orca = {
      url = "github:Udon0729/nixos-orca";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nixos-orca, ... }:
    {
      nixosConfigurations.matrix-mini = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-orca.nixosModules.default
          ./configuration.nix

          # Not in this repository. Generate it on the machine:
          #   nixos-generate-config --show-hardware-config > hardware-configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
}
