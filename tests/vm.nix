{ self, nixpkgs }:
{
  name = "orca-ide";

  nodes.machine =
    { pkgs, ... }:
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

      environment.systemPackages = [ pkgs.xdotool ];

      virtualisation = {
        memorySize = 4096;
        cores = 2;
      };
    };

  testScript = ''
    def as_alice(command):
        return f"su - alice -c 'DISPLAY=:0 {command}'"

    machine.wait_for_x()

    machine.succeed("grep -x 'Exec=orca-ide-desktop.*' /run/current-system/sw/share/applications/orca-ide.desktop")
    machine.succeed("ls /run/current-system/sw/share/icons/hicolor/*/apps/orca-ide.png")
    machine.succeed(as_alice("command -v orca-ide orca-ide-desktop orca"))

    machine.execute(as_alice("orca-ide-desktop >/tmp/orca-ide-desktop.log 2>&1 &"))
    machine.wait_until_succeeds(as_alice("xdotool search --onlyvisible --class orca"), timeout=300)
    machine.sleep(20)
    print(machine.succeed(as_alice("xwininfo -root -tree")))
    machine.screenshot("orca-window")

    print(machine.execute(as_alice("orca-ide status --json 2>&1"))[1])
    print(machine.execute(as_alice("orca status --json 2>&1"))[1])
    print(machine.execute("tail -n 60 /tmp/orca-ide-desktop.log")[1])
  '';
}
