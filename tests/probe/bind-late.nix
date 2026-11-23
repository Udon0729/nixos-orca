{ self }:
{
  name = "orca-server-bind-late";

  nodes.late = {
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
      # Not assigned at boot. The test adds it to eth1 five minutes later.
      bindAddress = "192.168.1.50";
    };
  };

  testScript = ''
    import datetime

    PORT = 6768
    ADDRESS = "192.168.1.50"

    def as_alice(command):
        return f"su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 {command}'"

    def show_state(machine):
        print(machine.execute(as_alice("systemctl --user status orca-server --no-pager -l"))[1])
        print(machine.execute(as_alice("journalctl --user -u orca-server --no-pager | tail -n 60"))[1])
        print(machine.execute("cat /home/alice/.local/state/orca-server/serve-supervisor-brake.json")[1])

    start_all()
    late.wait_for_unit("multi-user.target")
    late.fail(f"ip -4 -o address show | grep -qF '{ADDRESS}/'")

    with subtest("the address appears five minutes after boot"):
        late.succeed("sleep 300")
        show_state(late)
        late.succeed(f"ip address add {ADDRESS}/24 dev eth1")

    with subtest("the server comes up once its bind address exists"):
        try:
            # EXPECTED TO FAIL HERE: nothing starts the server any more.
            late.wait_until_succeeds(f"ss -ltnH | grep -qF ' {ADDRESS}:{PORT} '", timeout=datetime.timedelta(minutes=5))
        finally:
            show_state(late)
  '';
}
