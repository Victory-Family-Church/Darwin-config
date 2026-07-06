{ lib }:

# Builder helpers for turning vendor-distributed macOS installers (.dmg,
# .zip, .pkg) into ordinary Nix derivations, without depending on Homebrew.
#
# These are intentionally simple: they fetch a hash-pinned artifact and
# extract it. They do NOT try to reimplement what Apple's installer(8) does
# for .pkg files (running preinstall/postinstall scripts, registering
# launch daemons, requesting kernel extension approval, etc). For .pkg
# packages we instead hand a plain store path to
# modules/mac-app-activation.nix, which runs the real `/usr/sbin/installer`
# against it during darwin-rebuild activation -- that's the only way to get
# correct behavior for installer-driven software like Microsoft Office,
# Shure Wireless Workbench, or Dante Controller.

rec {
  # Extract a macOS .app bundle from a .dmg or .zip archive.
  # Produces $out/Applications/<appName>.
  mkAppFromArchive = pkgs:
    { pname
    , version
    , url
    , sha256
    , appName
    , kind # "dmg" | "zip"
    }:
    let
      unpackTool =
        if kind == "dmg" then pkgs.undmg
        else if kind == "zip" then pkgs.unzip
        else throw "mkAppFromArchive: unsupported kind '${kind}' for ${pname} (expected 'dmg' or 'zip')";
    in
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;
      src = pkgs.fetchurl { inherit url sha256; };
      nativeBuildInputs = [ unpackTool ];
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/Applications"
        if [ ! -d "${appName}" ]; then
          echo "error: expected '${appName}' after unpacking ${pname}-${version}, but found:" >&2
          ls -la >&2
          exit 1
        fi
        cp -R "${appName}" "$out/Applications/"
        runHook postInstall
      '';

      meta.platforms = pkgs.lib.platforms.darwin;
    };

  # Wrap a plain vendor .pkg installer as a hash-pinned store path.
  # Nothing is unpacked or run at build time.
  mkPkgInstaller = pkgs:
    { pname
    , version
    , url
    , sha256
    }:
    pkgs.fetchurl {
      inherit url sha256;
      name = "${pname}-${version}.pkg";
    };

  # Some vendors (e.g. Klang, whose KLANG:app download is a .zip containing
  # a .dmg containing the .app) wrap an app two layers deep. Unzip, then
  # undmg the .dmg found inside, then pull the .app out same as
  # mkAppFromArchive. Produces $out/Applications/<appName>.
  mkAppFromZippedDmg = pkgs:
    { pname
    , version
    , url
    , sha256
    , appName
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;
      src = pkgs.fetchurl { inherit url sha256; };
      nativeBuildInputs = [ pkgs.unzip pkgs.undmg ];
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        dmgFile="$(find . -maxdepth 2 -iname '*.dmg' -print -quit)"
        if [ -z "$dmgFile" ]; then
          echo "error: no .dmg found inside ${pname}-${version} zip, found:" >&2
          find . >&2
          exit 1
        fi
        undmg "$dmgFile"
        mkdir -p "$out/Applications"
        if [ ! -d "${appName}" ]; then
          echo "error: expected '${appName}' after unpacking the .dmg inside ${pname}-${version}.zip, but found:" >&2
          ls -la >&2
          exit 1
        fi
        cp -R "${appName}" "$out/Applications/"
        runHook postInstall
      '';

      meta.platforms = pkgs.lib.platforms.darwin;
    };

  # Same as mkAppFromArchive, but for a .dmg/.zip that's checked into the
  # repo (kindDetail "local") instead of fetched by URL -- `src` is a plain
  # local path, so there's no fetchurl/sha256 involved at all. Integrity
  # instead comes from git itself (the bytes are whatever's in the commit),
  # optionally cross-checked against packages.json's "localSha256" by the
  # overlay before this ever runs.
  mkAppFromLocalArchive = pkgs:
    { pname
    , version
    , src
    , appName
    , kind # "dmg" | "zip"
    }:
    let
      unpackTool =
        if kind == "dmg" then pkgs.undmg
        else if kind == "zip" then pkgs.unzip
        else throw "mkAppFromLocalArchive: unsupported kind '${kind}' for ${pname} (expected 'dmg' or 'zip')";
    in
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version src;
      nativeBuildInputs = [ unpackTool ];
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/Applications"
        if [ ! -d "${appName}" ]; then
          echo "error: expected '${appName}' after unpacking ${pname}-${version} (local), but found:" >&2
          ls -la >&2
          exit 1
        fi
        cp -R "${appName}" "$out/Applications/"
        runHook postInstall
      '';

      meta.platforms = pkgs.lib.platforms.darwin;
    };

  # Some vendors (e.g. Audinate/Dante Controller) ship their .pkg installer
  # wrapped inside a .dmg. Extract the inner .pkg with undmg so activation
  # still gets handed a plain .pkg path.
  mkPkgFromDmg = pkgs:
    { pname
    , version
    , url
    , sha256
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;
      src = pkgs.fetchurl { inherit url sha256; };
      nativeBuildInputs = [ pkgs.undmg ];
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        pkgFile="$(find . -maxdepth 2 -iname '*.pkg' -print -quit)"
        if [ -z "$pkgFile" ]; then
          echo "error: no .pkg found inside ${pname}-${version} dmg, found:" >&2
          find . >&2
          exit 1
        fi
        cp "$pkgFile" "$out/${pname}-${version}.pkg"
        runHook postInstall
      '';

      meta.platforms = pkgs.lib.platforms.darwin;
    };
}
