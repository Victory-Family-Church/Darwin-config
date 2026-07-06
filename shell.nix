# Dev shell for working on packages.json without touching the nix-darwin
# flake itself. Puts `update_packages.py` on PATH (as both its own name and
# a friendlier `update-packages` alias) so you can run it from anywhere,
# not just `python3 scripts/update_packages.py` from the repo root.
#
# Usage (run from the repo root -- see note below):
#   nix-shell
#   update-packages sync
#   update-packages pkg add <name> <kind> <version> <url> ...
#   update_packages.py pkg info reaper
{ pkgs ? import <nixpkgs> { } }:

let
  # Deliberately NOT `./scripts` here. Any Nix path gets copied into the
  # read-only /nix/store the moment it's interpolated into a string, which
  # would sever update_packages.py from the live, editable packages.json
  # sitting next to it in the actual checkout (that's what broke: the
  # script ran from a store copy whose parent directory had no
  # packages.json in it at all). $PWD is resolved by bash at the moment you
  # run `update-packages`/enter the shell, not by Nix at build time, so it
  # always points at your real working copy instead. This assumes you run
  # `nix-shell` / `update-packages` from the repo root, same as this repo's
  # README always shows.
  update-packages = pkgs.writeShellScriptBin "update-packages" ''
    exec ${pkgs.python3}/bin/python3 "$PWD/scripts/update_packages.py" "$@"
  '';
in
pkgs.mkShell {
  name = "nc-production-nix-darwin";

  packages = [
    pkgs.python3
    update-packages
  ];

  shellHook = ''
    export PATH="$PWD/scripts:$PATH"

    echo "nc-production-nix-darwin dev shell"
    echo "  update-packages list-all              # or: update_packages.py list-all"
    echo "  update-packages sync"
    echo "  update-packages pkg add|update|info|delete|revert ..."
  '';
}
