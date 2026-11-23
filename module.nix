{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.orca;
in
{
  options.programs.orca = {
    enable = lib.mkEnableOption "Orca, the desktop app from stablyai/orca";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The Orca package. It provides `orca-ide` (CLI) and `orca-ide-desktop` (app).";
    };

    shortCommand.enable = lib.mkEnableOption ''
      an `orca` command that runs the Orca CLI.
      It takes the name of the GNOME Orca screen reader, so it cannot be combined with `services.orca.enable`
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.shortCommand.enable && config.services.orca.enable);
        message = ''
          programs.orca.shortCommand.enable and services.orca.enable (the GNOME Orca screen reader,
          on by default in GNOME, Plasma, COSMIC, Cinnamon and Pantheon) both install `orca`.
          Use `orca-ide`, or set services.orca.enable = false.
        '';
      }
    ];

    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optional cfg.shortCommand.enable (
      pkgs.runCommand "orca-short-command" { } ''
        mkdir -p $out/bin
        ln -s ${lib.getExe cfg.package} $out/bin/orca
      ''
    );
  };
}
