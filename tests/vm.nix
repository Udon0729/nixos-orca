{ self, nixpkgs }:
{
  name = "orca-ide";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        self.nixosModules.default
        "${nixpkgs}/nixos/tests/common/x11.nix"
        "${nixpkgs}/nixos/tests/common/user-account.nix"
      ];

      test-support.displayManager.auto.user = "alice";

      programs.orca = {
        enable = true;
        shortCommand.enable = true;
      };

      environment.systemPackages = [
        pkgs.xdotool
        config.programs.orca.package.sandboxShell
        # Orca looks for ssh at /usr/bin/ssh before it falls back to PATH.
        (pkgs.writeShellScriptBin "check-system-ssh" ''
          set -eu
          test -x /usr/bin/ssh
          /usr/bin/ssh -V
        '')
      ];

      virtualisation = {
        memorySize = 4096;
        cores = 2;
      };
    };

  testScript = ''
    import json

    def as_alice(command):
        return f"su - alice -c 'DISPLAY=:0 {command}'"

    machine.wait_for_x()

    machine.succeed("grep -x 'Exec=orca-ide-desktop.*' /run/current-system/sw/share/applications/orca-ide.desktop")
    machine.succeed("ls /run/current-system/sw/share/icons/hicolor/*/apps/orca-ide.png")
    machine.succeed(as_alice("command -v orca-ide orca-ide-desktop orca"))

    with subtest("Orca finds a system ssh in both sandboxes"):
        check = "/run/current-system/sw/bin/check-system-ssh"
        machine.fail("test -e /usr/bin/ssh")
        print(machine.succeed("grep -ralF /usr/bin/ssh ${self.packages.x86_64-linux.default.contents}/resources | grep ."))
        print(machine.succeed(as_alice(f"orca-ide-sandbox-shell {check} 2>&1")))
        print(machine.succeed(as_alice(f"APPIMAGE_DEBUG_EXEC={check} orca-ide-desktop 2>&1")))

    machine.execute(as_alice("orca-ide-desktop >/tmp/orca-ide-desktop.log 2>&1 &"))
    machine.wait_until_succeeds(as_alice("xdotool search --onlyvisible --class orca"), timeout=300)
    machine.sleep(20)
    print(machine.succeed(as_alice("xwininfo -root -tree")))
    machine.screenshot("orca-window")

    for cli in ["orca-ide", "orca"]:
        status = json.loads(machine.succeed(as_alice(f"{cli} status --json")))
        runtime = status["result"]["runtime"]
        assert runtime["state"] == "ready", runtime
        assert runtime["appVersion"] == "${self.packages.x86_64-linux.default.version}", runtime
  '';
}
