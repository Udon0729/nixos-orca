{ self }:
{
  name = "orca-server";

  nodes.server = {
    imports = [ self.nixosModules.default ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
    };
    services.orca-server = {
      enable = true;
      user = "alice";
      interface = "eth1";
    };
    virtualisation.memorySize = 2048;
  };

  nodes.client = {
    imports = [ self.nixosModules.default ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
    };
    programs.orca.enable = true;
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    import re

    def as_alice(command):
        return f"su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 {command}'"

    def redact(text):
        return re.sub(r"(orca://pair\?)\S+", r"\1<redacted>", text)

    def show(machine, command):
        status, output = machine.execute(command + " 2>&1")
        print(f"$ {command}\n[exit {status}]\n{redact(output)}")
        return output

    start_all()
    address = "192.168.1.2"

    server.wait_for_unit("multi-user.target")
    server.wait_until_succeeds("ss -ltnH | grep -q ':6768 '", timeout=180)
    show(server, "ip -4 -o address")
    show(server, "ss -ltnp")
    show(server, as_alice("systemctl --user status orca-server --no-pager"))
    show(server, as_alice("journalctl --user -u orca-server --no-pager | tail -n 40"))
    show(server, "iptables -S | grep 6768")
    show(server, "ls -la /home/alice/.local/state/orca-server")

    show(server, as_alice(f"orca-server pair --address {address}"))
    show(server, as_alice(f"orca-server pair --mobile --address {address}"))
    show(server, as_alice("orca-server status --json"))
    show(server, as_alice("orca-server serve --help"))
    show(server, as_alice("orca-server environment --help"))
    show(server, as_alice("orca-server environment add --help"))

    client.wait_for_unit("multi-user.target")
    show(client, "timeout 3 bash -c \"</dev/tcp/server/6768\" && echo reachable")
  '';
}
