# In-repo overlay: adds `pkgs.macApps.<name>` for every vendor macOS app
# used across the NC production Macs (ProPresenter, Office, Dropbox,
# Blackmagic drivers, Dante/Shure audio tools, Tailscale, TeamViewer, ...).
#
# This replaces Homebrew casks entirely -- all of it is plain Nix, sourced
# from packages.json so `scripts/update_packages.py` can bump versions and
# hashes without touching this file.
#
# Each entry is one of:
#   { type = "app"; version; appName; drv; }   -- built from a .dmg/.zip
#   { type = "pkg"; version; pkgId;   src; }   -- a hash-pinned .pkg (fetched by
#                                                  URL, or checked into the repo
#                                                  for kindDetail == "local"), run
#                                                  by modules/mac-app-activation.nix
final: prev:
let
  lib = prev.lib;
  mac = import ../lib/mac-apps.nix { inherit lib; };

  manifest = (builtins.fromJSON (builtins.readFile ../packages.json)).packages;

  buildEntry = entry:
    if entry.kind == "zip" && (entry.kindDetail or null) == "zipContainsDmg" then {
      # e.g. Klang: KLANG:app ships as a .zip containing a .dmg containing
      # the .app -- two layers deep instead of one.
      type = "app";
      version = entry.version;
      appName = entry.appName;
      drv = mac.mkAppFromZippedDmg final {
        pname = entry.name;
        inherit (entry) version url sha256 appName;
      };
    }
    else if entry.kind == "zip" || entry.kind == "dmg" then {
      type = "app";
      version = entry.version;
      appName = entry.appName;
      drv = mac.mkAppFromArchive final {
        pname = entry.name;
        inherit (entry) version url sha256 appName kind;
      };
    }
    else if entry.kind == "pkg" && (entry.kindDetail or null) == "dmgContainsPkg" then {
      type = "pkg";
      version = entry.version;
      pkgId = entry.pkgId;
      src = mac.mkPkgFromDmg final {
        pname = entry.name;
        inherit (entry) version url sha256;
      };
    }
    else if entry.kind == "pkg" && (entry.kindDetail or null) == "local" then {
      # No fetchable URL at all (e.g. grandMA3 onPC's access-token-gated
      # download) -- the installer is checked into the repo itself at
      # entry.localPath and referenced directly, so there's nothing to
      # re-download, ever, and no token to expire. See vendor/README.md.
      type = "pkg";
      version = entry.version;
      pkgId = entry.pkgId;
      src = ../. + "/${entry.localPath}";
    }
    else if entry.kind == "pkg" then {
      type = "pkg";
      version = entry.version;
      pkgId = entry.pkgId;
      src = mac.mkPkgInstaller final {
        pname = entry.name;
        inherit (entry) version url sha256;
      };
    }
    else throw "overlays/production-apps.nix: unknown kind '${entry.kind}' for package '${entry.name}'";
in
{
  macApps = builtins.listToAttrs (map (e: { name = e.name; value = buildEntry e; }) manifest);
}
