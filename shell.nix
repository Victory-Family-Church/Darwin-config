# Dev shell for working on packages.json without touching the nix-darwin
# flake itself. Puts `update_packages.py` on PATH (as both its own name and
# a friendlier `update-packages` alias) so you can run it from anywhere,
# not just `python3 scripts/update_packages.py` from the repo root.
#
# Usage:
#   nix-shell
#   update-packages sync
#   update-packages pkg add <name> <kind> <version> <url> ...
#   update_packages.py pkg info reaper
{ pkgs ? import <nixpkgs> { } }:

let
  scriptsDir = ./scripts;

  # Thin wrapper so `update-packages` works regardless of $PWD or whether
  # scripts/update_packages.py's executable bit survived a checkout.
  update-packages = pkgs.writeShellScriptBin "update-packages" ''
    exec ${pkgs.python3}/bin/python3 ${scriptsDir}/update_packages.py "$@"
  '';
in
pkgs.mkShell {
  name = "nc-production-nix-darwin";

  packages = [
    pkgs.python3
    update-packages
  ];

  shellHook = ''
    export PATH="${toString scriptsDir}:$PATH"

    echo "nc-production-nix-darwin dev shell"
    echo "  update-packages list-all              # or: update_packages.py list-all"
    echo "  update-packages sync"
    echo "  update-packages pkg add|update|info|delete|revert ..."
  '';
}
