{ self }:
{
  name = "orca-server-crash-brake";

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

    def address_of(machine, interface):
        return machine.succeed(f"ip -4 -o address show dev {interface} | awk '{{ sub(/\\/.*/, \"\", $4); print $4 }}'").strip()

    def wait_for_listener(machine, local):
        machine.wait_until_succeeds(f"ss -ltnH | grep -qF ' {local} '", timeout=datetime.timedelta(minutes=3))

    def runtime_pid(machine):
        pid = machine.succeed(f"ss -ltnpH 'sport = :{PORT}' | grep -o 'pid=[0-9]*' | cut -d= -f2").strip()
        assert pid, "no runtime listens"
        return pid

    def show_state(machine):
        print(machine.execute(as_alice("systemctl --user status orca-server --no-pager -l"))[1])
        print(machine.execute(as_alice("journalctl --user -u orca-server --no-pager | grep -F \"[serve]\" | tail -n 30"))[1])
        print(machine.execute("cat /home/alice/.local/state/orca-server/serve-supervisor-brake.json")[1])

    start_all()
    pinned.wait_for_unit("multi-user.target")
    address = address_of(pinned, "eth1")
    local = f"{address}:{PORT}"
    wait_for_listener(pinned, local)

    with subtest("the runtime crashes six times within a few minutes"):
        for crash in range(1, 7):
            pid = runtime_pid(pinned)
            pinned.succeed(f"kill -KILL {pid}")
            pinned.wait_until_fails(f"kill -0 {pid}")
            if crash < 6:
                wait_for_listener(pinned, local)
        pinned.succeed("sleep 60")
        show_state(pinned)

    with subtest("after a reboot the server stays down, by Orca's own crash limit"):
        pinned.shutdown()
        pinned.start()
        pinned.wait_for_unit("multi-user.target")
        pinned.wait_until_succeeds(as_alice("journalctl --user -u orca-server --no-pager") + " | grep -qF 'Not starting'")
        pinned.succeed("sleep 30")
        show_state(pinned)
        pinned.fail(f"ss -ltnH | grep -qF ' {local} '")

    with subtest("removing the crash record and restarting the unit brings it back"):
        pinned.succeed(as_alice("systemctl --user stop orca-server"))
        pinned.succeed("rm /home/alice/.local/state/orca-server/serve-supervisor-brake.json")
        pinned.succeed(as_alice("systemctl --user start orca-server"))
        wait_for_listener(pinned, local)
        show_state(pinned)
  '';
}
