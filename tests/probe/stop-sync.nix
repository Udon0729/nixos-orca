{ self }:
{
  name = "orca-server-stop-sync";

  nodes.pinned = {
    imports = [ self.nixosModules.default ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
    };
    virtualisation.memorySize = 2048;
    services.orca-server = {
      enable = true;
      user = "alice";
      interface = "eth1";
    };
  };

  testScript = ''
    import datetime

    PORT = 6768

    def as_alice(command):
        return f"su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 {command}'"

    start_all()
    pinned.wait_for_unit("multi-user.target")
    pinned.wait_until_succeeds(f"ss -ltnH | grep -qF ':{PORT} '", timeout=datetime.timedelta(minutes=3))

    with subtest("when stop returns, the server no longer listens"):
        # One command, so nothing runs between the stop and the check.
        status, output = pinned.execute(as_alice("systemctl --user stop orca-server") + f"; ss -ltnpH 'sport = :{PORT}'")
        print(output)
        print(pinned.execute(as_alice("journalctl --user -u orca-server --no-pager | tail -n 8"))[1])
        # EXPECTED TO FAIL HERE: the runtime still holds the port.
        assert f":{PORT}" not in output, "still listening after stop returned: " + output
  '';
}
