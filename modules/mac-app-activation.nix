{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.production.macApps;

  missing = filter (n: !(hasAttr n pkgs.macApps)) cfg.apps;

  entries = map (n: { n = n; app = pkgs.macApps.${n}; })
    (filter (n: hasAttr n pkgs.macApps) cfg.apps);

  appEntries = filter (e: e.app.type == "app") entries;
  pkgEntries = filter (e: e.app.type == "pkg") entries;
  installerAppEntries = filter (e: e.app.type == "installer-app") entries;

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

  # "installer-app" packages (currently just Spotify: "Install Spotify.app"
  # is a standalone executable that has to be *run* to install
  # "Spotify.app", not copied/symlinked, and not an Apple .pkg receipt
  # installer(8) understands) can't be handled from the root
  # activation-script context, same reasoning as desktoppr in
  # modules/wallpaper.nix: running a GUI installer needs a real
  # login/WindowServer session, which a non-interactive root script during
  # darwin-rebuild doesn't have. So this runs from a LaunchAgent instead,
  # firing at login for whichever CG-* account is logged in (autologin, so
  # effectively at every boot), and is idempotent by checking whether
  # `/Applications/<appName>` already exists.
  installerAppLaunchAgents = builtins.listToAttrs (map
    (e: {
      name = "nc-install-${e.n}";
      value = {
        serviceConfig = {
          ProgramArguments = [
            "/bin/sh"
            "-c"
            ''
              if [ -e "/Applications/${e.app.appName}" ]; then
                echo "macApps: ${e.n} already installed (/Applications/${e.app.appName} exists)"
              else
                echo "macApps: running installer for ${e.n}: ${e.app.installerAppName}"
                /usr/bin/open -W "${e.app.src}"
              fi
            ''
          ];
          RunAtLoad = true;
          StandardOutPath = "/tmp/nc-install-${e.n}.log";
          StandardErrorPath = "/tmp/nc-install-${e.n}.log";
        };
      };
    })
    installerAppEntries);
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
      - "installer-app" packages (e.g. Spotify's "Install Spotify.app") are
        standalone executable installers, not Apple .pkg receipts or
        drag-install apps -- run once via a LaunchAgent at login (needs a
        real WindowServer session, so it can't happen from the root
        activation script), idempotent by checking whether
        `/Applications/<appName>` already exists.
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

    launchd.user.agents = installerAppLaunchAgents;
  };
}
