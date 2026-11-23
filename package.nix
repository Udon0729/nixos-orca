{
  lib,
  appimageTools,
  buildFHSEnv,
  fetchurl,
}:
let
  source = lib.importJSON ./sources.json;
  inherit (source) version;

  contents = appimageTools.extract {
    pname = "orca-ide";
    inherit version;
    src = fetchurl { inherit (source) url hash; };
  };

  # Orca keeps daemons and terminals alive after the launching process exits.
  dieWithParent = false;

  # Programs that Orca starts by absolute path, so they must exist in /usr/bin of the sandbox.
  extraPkgs = pkgs: [ ];

  desktop = appimageTools.wrapAppImage {
    pname = "orca-ide-desktop";
    inherit version dieWithParent extraPkgs;
    src = contents;
  };

  cliEnv = appimageTools.defaultFhsEnvArgs // {
    inherit version dieWithParent;
    targetPkgs = pkgs: appimageTools.defaultFhsEnvArgs.targetPkgs pkgs ++ extraPkgs pkgs;
  };
in
buildFHSEnv (
  cliEnv
  // {
    pname = "orca-ide";

    # Upstream's CLI shim. The .deb links the same file to /usr/bin/orca-ide.
    runScript = "${contents}/resources/bin/orca-ide";

    extraInstallCommands = ''
      ln -s ${desktop}/bin/orca-ide-desktop $out/bin/orca-ide-desktop

      install -Dm444 ${contents}/orca-ide.desktop $out/share/applications/orca-ide.desktop
      sed -i 's|^Exec=AppRun|Exec=orca-ide-desktop|' $out/share/applications/orca-ide.desktop
      grep -q '^Exec=orca-ide-desktop' $out/share/applications/orca-ide.desktop

      cp -r ${contents}/usr/share/icons $out/share/icons
    '';

    passthru = {
      inherit contents desktop;
      # A shell in the same sandbox as the CLI, for tests.
      sandboxShell = buildFHSEnv (
        cliEnv
        // {
          pname = "orca-ide-sandbox-shell";
          runScript = "bash";
        }
      );
    };

    meta = {
      description = "Orca, a desktop app that runs coding agents in parallel (stablyai/orca)";
      homepage = "https://github.com/stablyai/orca";
      license = lib.licenses.mit;
      mainProgram = "orca-ide";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
)
