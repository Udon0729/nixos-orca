{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.orca-server;
  dataDir = "${config.users.users.${cfg.user}.home}/.local/state/orca-server";

  # Orca creates pairing offers on demand (`orca-ide pair`, and every mobile offer) only on a
  # listener that covers all interfaces. With mobilePairing the firewall rule is what keeps the
  # port to cfg.interface. --no-pairing keeps the start-up offer out of the journal.
  listenFlags =
    if cfg.mobilePairing then ''--bind 0.0.0.0 --no-pairing'' else ''--bind "$address"'';

  start = pkgs.writeShellScript "orca-server-start" ''
    set -eu
    address=${lib.escapeShellArg (if cfg.bindAddress == null then "" else cfg.bindAddress)}
    while [ -z "$address" ]; do
      address="$(${pkgs.iproute2}/bin/ip -4 -o address show dev ${lib.escapeShellArg cfg.interface} scope global 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{ sub(/\/.*/, "", $4); print $4; exit }')"
      if [ -z "$address" ]; then
        echo "waiting for an IPv4 address on ${cfg.interface}"
        sleep 5
      fi
    done
    ${pkgs.coreutils}/bin/install -d -m 700 ${lib.escapeShellArg dataDir}
    exec ${lib.getExe cfg.package} serve --supervise --refuse-public \
      --port ${toString cfg.port} ${listenFlags} --pairing-address "$address"
  '';
in
{
  options.services.orca-server = {
    enable = lib.mkEnableOption "a headless Orca runtime (`orca-ide serve`) that other Orca clients pair with";

    package = lib.mkOption {
      type = lib.types.package;
      default = config.programs.orca.package;
      defaultText = lib.literalExpression "config.programs.orca.package";
      description = "The Orca package that provides `orca-ide`.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      example = "owner";
      description = ''
        The normal user that owns the runtime. The service is a systemd user unit of this user,
        and the user gets lingering so the unit starts at boot without a login.
      '';
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = ''
        The only interface on which the firewall opens the port. Unless `bindAddress` is set,
        the server also waits for this interface's IPv4 address and binds to it.
      '';
    };

    bindAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "100.64.1.20";
      description = ''
        A literal IP address to put in pairing links, instead of the address of `interface`.
        The server also binds to it, unless `mobilePairing` is on. Then the server binds to 0.0.0.0.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6768;
      description = "The TCP port of the runtime.";
    };

    mobilePairing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow pairing the Orca mobile app, and pairing on demand with `orca-server pair`.
        Orca serves both only from a listener on all interfaces, so this makes the server listen
        on 0.0.0.0. The firewall still opens the port on `interface` alone.

        When this is off, the server listens on one address. It then cannot make pairing links
        while it runs as a service. Stop the unit and run `orca-server serve` once in a terminal
        to pair a desktop client.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open `port` in the firewall on `interface`, and on no other interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # Linux accepts packets for any local address on any interface, so a listener bound to
        # one address is still reachable from other networks unless the firewall drops them.
        assertion = config.networking.firewall.enable;
        message = ''
          services.orca-server relies on the firewall to keep its port to ${cfg.interface}.
          networking.firewall.enable must be true.
        '';
      }
      {
        assertion = config.users.users.${cfg.user}.isNormalUser;
        message = "services.orca-server.user must be a normal user (isNormalUser), not root or a system user.";
      }
    ];

    users.users.${cfg.user}.linger = true;

    networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    environment.systemPackages = [
      cfg.package
      (pkgs.writeShellScriptBin "orca-server" ''
        export ORCA_USER_DATA_PATH=${lib.escapeShellArg dataDir}
        exec ${lib.getExe cfg.package} "$@"
      '')
    ];

    # Mirrors the unit that `orca-ide serve service install` writes.
    systemd.user.services.orca-server = {
      description = "Orca server (orca-ide serve --supervise)";
      wantedBy = [ "default.target" ];
      unitConfig = {
        ConditionUser = cfg.user;
        StartLimitIntervalSec = 900;
        StartLimitBurst = 5;
      };
      environment.ORCA_USER_DATA_PATH = dataDir;
      path = [
        "/run/wrappers"
        "/etc/profiles/per-user/${cfg.user}"
        "/run/current-system/sw"
      ];
      serviceConfig = {
        ExecStart = start;
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStopSec = 90;
        # The main process is the bubblewrap wrapper, which does not forward signals. Its child is
        # Orca's supervisor, which stops the server on SIGTERM and leaves the terminal daemon alone.
        ExecStop = "${pkgs.procps}/bin/pkill -TERM -P $MAINPID";
        KillMode = "process";
      };
    };
  };
}
