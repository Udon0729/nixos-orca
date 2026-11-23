{
  description = "Orca (stablyai/orca) for NixOS: AppImage package, NixOS module, VM test";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.callPackage ./package.nix { };

      nixosModules.default.imports = [
        ./module.nix
        ./server-module.nix
      ];

      checks.${system} = {
        package = self.packages.${system}.default;
        vm = pkgs.testers.runNixOSTest (import ./tests/vm.nix { inherit self nixpkgs; });
        server = pkgs.testers.runNixOSTest (import ./tests/server.nix { inherit self; });
        existing-config = import ./tests/existing-config.nix { inherit self nixpkgs pkgs; };
      };
    };
}
