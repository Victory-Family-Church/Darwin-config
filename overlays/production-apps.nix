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

  # For kindDetail == "local" entries: resolve entry.localPath (repo-relative)
  # to a plain Nix path (no fetchurl -- the bytes just are whatever's
  # checked into the repo at that path). If packages.json also carries a
  # "localSha256" (written by `scripts/update_packages.py pkg update <name>
  # <version>`), cross-check it here so a vendor file that got
  # swapped/corrupted without updating packages.json fails the build loudly
  # instead of silently installing the wrong bits.
  localSrc = entry:
    let
      path = ../. + "/${entry.localPath}";
      expected = entry.localSha256 or null;
    in
    if expected == null then path
    else
      let actual = builtins.hashFile "sha256" path; in
      if actual != expected then
        throw ''
          overlays/production-apps.nix: ${entry.name} at ${entry.localPath} has sha256
            ${actual}
          but packages.json's "localSha256" says
            ${expected}
          Either the vendor file changed without updating packages.json (run
          `python3 scripts/update_packages.py pkg update ${entry.name} <version>` to refresh it),
          or vendor/${entry.localPath} is genuinely the wrong file.
        ''
      else path;

  # For kindDetail == "external" entries: entry.localPath is an *absolute*
  # host filesystem path (e.g. /Users/Shared/nc-vendor/foo.pkg) that lives
  # completely outside this repo/git -- some vendor installers (grandMA3
  # onPC, Blackmagic Desktop Video) are simply too large for a normal
  # GitHub push (100MB hard limit without Git LFS), so these are placed by
  # hand on each Mac instead of committed anywhere. Deliberately kept as a
  # plain string, not a Nix `path` value: interpolating a real `path` into
  # a derivation always copies it into the (read-only, versioned) Nix
  # store, which is exactly wrong for a large file that's meant to just sit
  # on disk outside Nix's purview. `builtins.hashFile` can still read an
  # absolute string path directly at eval time for the same integrity check
  # as the "local" case, with no store copy involved.
  externalSrc = entry:
    let
      path = entry.localPath;
      expected = entry.localSha256 or null;
    in
    if expected == null then path
    else
      let actual = builtins.hashFile "sha256" path; in
      if actual != expected then
        throw ''
          overlays/production-apps.nix: ${entry.name} at ${path} has sha256
            ${actual}
          but packages.json's "localSha256" says
            ${expected}
          Either the file at that path changed without updating packages.json (run
          `python3 scripts/update_packages.py pkg update ${entry.name} <version>` to refresh it),
          or ${path} is genuinely the wrong file. Make sure you've actually placed
          the real installer at that exact path on this Mac -- see vendor/README.md.
        ''
      else path;

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
    else if (entry.kind == "zip" || entry.kind == "dmg") && (entry.kindDetail or null) == "local" then {
      # A .dmg/.zip checked into the repo (small enough for git). Nothing
      # currently in packages.json uses this -- see "external" below,
      # which is what actually-large files like grandMA3/Blackmagic use --
      # but it's kept available for any future small enough vendor file.
      type = "app";
      version = entry.version;
      appName = entry.appName;
      drv = mac.mkAppFromLocalArchive final {
        pname = entry.name;
        inherit (entry) version appName kind;
        src = localSrc entry;
      };
    }
    else if (entry.kind == "zip" || entry.kind == "dmg") && (entry.kindDetail or null) == "external" then {
      # e.g. Spotify: pinned to a specific downloaded build instead of
      # always tracking whatever's currently live at download.scdn.co, and
      # placed at a fixed absolute path outside git (see externalSrc above
      # and vendor/README.md) rather than committed.
      type = "app";
      version = entry.version;
      appName = entry.appName;
      drv = mac.mkAppFromLocalArchive final {
        pname = entry.name;
        inherit (entry) version appName kind;
        src = externalSrc entry;
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
      # A .pkg checked into the repo (small enough for git). Nothing
      # currently in packages.json uses this -- see "external" below.
      type = "pkg";
      version = entry.version;
      pkgId = entry.pkgId;
      src = localSrc entry;
    }
    else if entry.kind == "pkg" && (entry.kindDetail or null) == "external" then {
      # No fetchable URL at all (grandMA3 onPC's access-token-gated
      # download, Blackmagic/Audinate's account-gated portals) *and* these
      # installers run 700MB-plus, well past what a normal GitHub push (or
      # even Git LFS's free tier) can take -- so these are never committed
      # anywhere. They're placed by hand at a fixed absolute path on each
      # Mac (see externalSrc above), typically via
      # `scripts/update_packages.py provision`. See vendor/README.md.
      type = "pkg";
      version = entry.version;
      pkgId = entry.pkgId;
      src = externalSrc entry;
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
