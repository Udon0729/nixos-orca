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
    import datetime
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
        machine.wait_until_succeeds(f"ss -ltnH | grep -qF ' {local} '", timeout=datetime.timedelta(minutes=3))

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

    def runtime_pid(machine):
        return machine.succeed(f"ss -ltnpH 'sport = :{PORT}' | grep -o 'pid=[0-9]*' | cut -d= -f2").strip()

    with subtest("pinned: Orca's supervisor restarts the runtime after it is killed"):
        first_pid = runtime_pid(pinned)
        pinned.succeed(f"kill -KILL {first_pid}")
        pinned.wait_until_fails(f"kill -0 {first_pid}")
        wait_for_listener(pinned, f"{pinned_address}:{PORT}")
        second_pid = runtime_pid(pinned)
        assert second_pid != first_pid
        assert unit_property(pinned, "NRestarts") == "0"

    with subtest("pinned: systemd restarts the unit after every process in it is killed"):
        pinned.succeed(as_alice("systemctl --user kill --signal=KILL orca-server"))
        pinned.wait_until_fails(f"kill -0 {second_pid}")
        pinned.wait_until_succeeds(as_alice("systemctl --user show orca-server --property NRestarts --value") + " | grep -qx 1")
        wait_for_listener(pinned, f"{pinned_address}:{PORT}")
        assert runtime_pid(pinned) != second_pid
        show(pinned, as_alice("systemctl --user status orca-server --no-pager"))

    with subtest("pinned: a foreground run prints a pairing link, and the grant survives the service restart"):
        assert "orca://pair" not in pinned.succeed(as_alice("journalctl --user -u orca-server --no-pager"))
        pinned.succeed(as_alice("systemctl --user stop orca-server"))
        pinned.wait_until_fails(f"ss -ltnH | grep -qF ':{PORT} '")
        pinned.succeed(as_alice(f"orca-server serve --refuse-public --port {PORT} --bind {pinned_address} --pairing-address {pinned_address} >/tmp/foreground.log 2>&1 &"))
        pinned.wait_until_succeeds("grep -q 'orca://pair' /tmp/foreground.log", timeout=datetime.timedelta(minutes=3))
        pair_client("pinned", pairing_link(pinned.succeed("cat /tmp/foreground.log")))
        show(pinned, "pkill -INT -u alice -f 'cli/index.js serve'; sleep 10; ss -ltnp")
        pinned.succeed(as_alice("systemctl --user start orca-server"))
        wait_for_listener(pinned, f"{pinned_address}:{PORT}")
        show(client, as_alice("orca-ide status --environment pinned --json"))

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
