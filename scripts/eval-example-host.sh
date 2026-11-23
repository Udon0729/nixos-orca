#!/usr/bin/env bash
# Evaluates examples/host against this checkout and its nixpkgs pin, with the CI hardware stub.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT
cp examples/host/*.nix "$work/"
cp ci/hardware-configuration.stub.nix "$work/hardware-configuration.nix"

nixpkgs_rev="$(jq -r .nodes.nixpkgs.locked.rev flake.lock)"
nix eval --raw --no-write-lock-file \
  --override-input nixos-orca "path:$PWD" \
  --override-input nixpkgs "github:NixOS/nixpkgs/$nixpkgs_rev" \
  "path:$work#nixosConfigurations.matrix-mini.config.system.build.toplevel.drvPath"
echo
