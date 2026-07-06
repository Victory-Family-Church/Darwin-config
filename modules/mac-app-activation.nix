{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.production.macApps;

  missing = filter (n: !(hasAttr n pkgs.macApps)) cfg.apps;

  entries = map (n: { n = n; app = pkgs.macApps.${n}; })
    (filter (n: hasAttr n pkgs.macApps) cfg.apps);

  appEntries = filter (e: e.app.type == "app") entries;
  pkgEntries = filter (e: e.app.type == "pkg") entries;

  linkAppScript = e: ''
    target="/Applications/${e.app.appName}"
    desired="${e.app.drv}/Applications/${e.app.appName}"
    if [ ! -e "$target" ] || [ "$(readlink "$target" 2>/dev/null)" != "$desired" ]; then
      echo "macApps: linking ${e.n} -> $target"
      rm -rf "$target"
      ln -sfn "$desired" "$target"
    fi
  '';

  installPkgScript = e: ''
    if /usr/sbin/pkgutil --pkg-info "${e.app.pkgId}" >/dev/null 2>&1; then
      echo "macApps: ${e.n} already installed (pkgId ${e.app.pkgId})"
    else
      echo "macApps: installing ${e.n} from ${e.app.src}"
      /usr/sbin/installer -pkg "${e.app.src}" -target / || echo "macApps: WARNING - ${e.n} installer exited non-zero"
    fi
  '';
in
{
  options.production.macApps.apps = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      Names of packages (keys under `pkgs.macApps`, defined in
      packages.json and built by overlays/production-apps.nix) to install
      on this host.

      - "app" packages (fetched .dmg/.zip, e.g. ProPresenter, Dropbox) are
        symlinked into /Applications during activation.
      - "pkg" packages (vendor .pkg installers, e.g. Microsoft Word,
        Tailscale, Wireless Workbench) are installed once via
        `/usr/sbin/installer` and are idempotent, keyed off
        `pkgutil --pkg-info <pkgId>`.
    '';
    example = [ "propresenter" "dropbox" "tailscale" ];
  };

  config = {
    assertions = [
      {
        assertion = missing == [ ];
        message =
          "production.macApps.apps references unknown package(s): "
          + concatStringsSep ", " missing
          + ". Check the \"name\" fields in packages.json.";
      }
    ];

    # NOTE: written against a recent nix-darwin `master`. If
    # `system.activationScripts.postActivation` has moved/renamed in the
    # nix-darwin release you pin, `darwin-rebuild build` will tell you --
    # adjust the key below to match.
    system.activationScripts.postActivation.text = mkAfter (''
      echo "== NC production macApps =="
    ''
    + concatStringsSep "\n" (map linkAppScript appEntries)
    + "\n"
    + concatStringsSep "\n" (map installPkgScript pkgEntries));
  };
}
