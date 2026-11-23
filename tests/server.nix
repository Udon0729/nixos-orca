{ self }:
let
  common = {
    imports = [ self.nixosModules.default ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
    };
    virtualisation.memorySize = 2048;
  };
in
{
  name = "orca-server";

  # eth1 (VLAN 1) stands in for the Tailscale interface. eth2 (VLAN 2) is a network that must stay closed.
  nodes.pinned = {
    imports = [ common ];
    services.orca-server = {
      enable = true;
      user = "alice";
      interface = "eth1";
    };
  };

  nodes.wide = {
    imports = [ common ];
    virtualisation.vlans = [
      1
      2
    ];
    services.orca-server = {
      enable = true;
      user = "alice";
      interface = "eth1";
      mobilePairing = true;
    };
  };

  nodes.client = {
    imports = [ common ];
    virtualisation.vlans = [
      1
      2
    ];
    programs.orca.enable = true;
  };

  testScript = ''
    import re

    PORT = 6768
    FIREWALL_RULE = f"-A nixos-fw -i eth1 -p tcp -m tcp --dport {PORT} -j nixos-fw-accept"

    def as_alice(command):
        return f"su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 {command}'"

    def redact(text):
        return re.sub(r"(orca://pair\?)\S+", r"\1<redacted>", text)

    def show(machine, command):
        status, output = machine.execute(command + " 2>&1")
        print(f"$ {command}\n[exit {status}]\n{redact(output)}")
        return output

    def address_of(machine, interface):
        return machine.succeed(f"ip -4 -o address show dev {interface} | awk '{{ sub(/\\/.*/, \"\", $4); print $4 }}'").strip()

    def listeners(machine):
        print(machine.succeed("ss -ltnp"))
        return [line.split()[3] for line in machine.succeed("ss -ltnH").splitlines()]

    def wait_for_listener(machine, local):
        machine.wait_until_succeeds(f"ss -ltnH | grep -qF ' {local} '", timeout=180)

    def unit_property(machine, name):
        return machine.succeed(as_alice(f"systemctl --user show orca-server --property {name} --value")).strip()

    def pairing_link(text):
        match = re.search(r"orca://pair\?\S+", text)
        assert match, "no pairing link in: " + redact(text)
        print("pairing link: " + redact(match.group(0)))
        return match.group(0)

    def pair_client(name, link):
        client.succeed(f"cat > /tmp/{name}.link <<'EOF'\n{link}\nEOF")
        show(client, as_alice(f"orca-ide environment add --name {name} --pairing-code \"$(cat /tmp/{name}.link)\""))
        show(client, as_alice("orca-ide environment list"))
        show(client, as_alice(f"orca-ide status --environment {name} --json"))

    start_all()

    with subtest("pinned: the user unit starts at boot and listens on eth1 only"):
        pinned.wait_for_unit("multi-user.target")
        pinned_address = address_of(pinned, "eth1")
        wait_for_listener(pinned, f"{pinned_address}:{PORT}")
        for local in listeners(pinned):
            assert local == f"{pinned_address}:{PORT}" or local.startswith("127.0.0.1:"), local
        assert pinned.succeed(f"iptables -S | grep -- '--dport {PORT}'").strip() == FIREWALL_RULE
        client.succeed(f"timeout 5 bash -c '</dev/tcp/{pinned_address}/{PORT}'")

    with subtest("pinned: each start prints one pairing link, and a client can use it"):
        journal = pinned.succeed(as_alice("journalctl --user -u orca-server --no-pager"))
        pair_client("pinned", pairing_link(journal))

    with subtest("pinned: the runtime comes back after it is killed"):
        runtime_pid = pinned.succeed(f"ss -ltnpH 'sport = :{PORT}' | grep -o 'pid=[0-9]*' | cut -d= -f2").strip()
        pinned.succeed(f"kill -KILL {runtime_pid}")
        pinned.wait_until_fails(f"kill -0 {runtime_pid}")
        wait_for_listener(pinned, f"{pinned_address}:{PORT}")
        show(pinned, as_alice("journalctl --user -u orca-server --no-pager | tail -n 25"))

    with subtest("pinned: systemd restarts the unit after its main process is killed"):
        main_pid = unit_property(pinned, "MainPID")
        pinned.succeed(f"kill -KILL {main_pid}")
        show(pinned, "sleep 45")
        show(pinned, as_alice("systemctl --user status orca-server --no-pager"))
        print("NRestarts:", unit_property(pinned, "NRestarts"), "MainPID:", main_pid, "->", unit_property(pinned, "MainPID"))
        show(pinned, as_alice("journalctl --user -u orca-server --no-pager | tail -n 30"))
        listeners(pinned)

    with subtest("wide: listens on all interfaces, and the firewall opens eth1 only"):
        wide.wait_for_unit("multi-user.target")
        wait_for_listener(wide, f"0.0.0.0:{PORT}")
        listeners(wide)
        assert wide.succeed(f"iptables -S | grep -- '--dport {PORT}'").strip() == FIREWALL_RULE
        wide_address = address_of(wide, "eth1")
        client.succeed(f"timeout 5 bash -c '</dev/tcp/{wide_address}/{PORT}'")
        client.succeed(f"ping -c 1 {address_of(wide, 'eth2')}")
        client.fail(f"timeout 5 bash -c '</dev/tcp/{address_of(wide, 'eth2')}/{PORT}'")

    with subtest("wide: pairing links are made on demand, for desktop and for mobile"):
        assert "orca://pair" not in wide.succeed(as_alice("journalctl --user -u orca-server --no-pager"))
        desktop_link = pairing_link(wide.succeed(as_alice(f"orca-server pair --address {wide_address}")))
        status, mobile_output = wide.execute(as_alice(f"orca-server pair --mobile --address {wide_address}") + " 2>&1")
        print("mobile pair exit:", status, "lines:", len(mobile_output.splitlines()), [redact(line) for line in mobile_output.splitlines() if "://" in line])
        pair_client("wide", desktop_link)
  '';
}
