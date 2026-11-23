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

  refused =
    settings:
    !(builtins.tryEval
      (evaluate [
        self.nixosModules.default
        settings
      ]).system.build.toplevel.drvPath
    ).success;

  server = extra: { services.orca-server = { enable = true; } // extra; };

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
assert !refused (server { user = "owner"; });
assert refused { imports = [ (server { user = "owner"; }) ]; networking.firewall.enable = false; };
assert refused { imports = [ (server { user = "owner"; mobilePairing = true; }) ]; networking.firewall.enable = false; };
assert refused (server { user = "root"; });
pkgs.runCommand "existing-config-check" { } ''
  echo "importing the module without enabling it leaves the system derivation unchanged" > $out
''
