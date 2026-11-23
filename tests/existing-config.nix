# Evaluation-only check: what the module does to a configuration that already uses
# Plasma, Tailscale and its own firewall rule on tailscale0.
{
  self,
  nixpkgs,
  pkgs,
}:
let
  existing = {
    imports = [ ../ci/hardware-configuration.stub.nix ];
    boot.loader.systemd-boot.enable = true;
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm.enable = true;
    services.tailscale.enable = true;
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
    users.users.owner.isNormalUser = true;
    system.stateVersion = "26.11";
  };

  evaluate = modules: (nixpkgs.lib.nixosSystem { modules = [ existing ] ++ modules; }).config;

  untouched = evaluate [ ];
  imported = evaluate [ self.nixosModules.default ];
  enabled = evaluate [
    self.nixosModules.default
    {
      programs.orca.enable = true;
      services.orca-server = {
        enable = true;
        user = "owner";
        mobilePairing = true;
      };
    }
  ];

  withoutFirewall = evaluate [
    self.nixosModules.default
    {
      networking.firewall.enable = false;
      services.orca-server = {
        enable = true;
        user = "owner";
        mobilePairing = true;
      };
    }
  ];

  firewall = config: {
    inherit (config.networking.firewall) allowedTCPPorts allowedUDPPorts trustedInterfaces;
    interfaces = builtins.mapAttrs (_: i: i.allowedTCPPorts) config.networking.firewall.interfaces;
  };
in
assert imported.system.build.toplevel.drvPath == untouched.system.build.toplevel.drvPath;
assert
  firewall enabled
  == firewall untouched
  // {
    interfaces.tailscale0 = [
      22
      6768
    ];
  };
assert enabled.users.users.owner.linger == true && untouched.users.users.owner.linger != true;
assert enabled.services.orca.enable == untouched.services.orca.enable;
assert enabled.systemd.services.tailscaled.serviceConfig == untouched.systemd.services.tailscaled.serviceConfig;
assert !(builtins.tryEval withoutFirewall.system.build.toplevel.drvPath).success;
pkgs.runCommand "existing-config-check" { } ''
  echo "importing the module without enabling it leaves the system derivation unchanged" > $out
''
