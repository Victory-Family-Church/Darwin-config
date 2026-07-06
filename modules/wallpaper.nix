# Generates a desktop wallpaper (background color + optional foreground
# logo + hostname watermark in the bottom-left corner) and sets it on
# every NC production Mac.
#
# Uses `desktoppr` (https://github.com/scriptingosx/desktoppr) driven by a
# LaunchAgent, rather than `osascript ... tell "System Events"`: osascript
# needs a live, permitted Automation session and routinely no-ops when run
# from a non-interactive root activation script during darwin-rebuild.
# desktoppr is purpose-built to be run from a LaunchAgent instead, which is
# what happens here -- it fires at login for whichever CG-* account is
# logged in (autologin, so effectively at every boot).
{ config, lib, pkgs, hostName, ... }:

with lib;

let
  cfg = config.production.wallpaper;

  mkWallpaper = import ../lib/mk-wallpaper.nix { inherit pkgs lib; };

  wallpaperImage = mkWallpaper {
    inherit (cfg) backgroundColor foregroundImage foregroundScale width height font fontSize textColor margin;
    hostname = hostName;
  };
in
{
  options.production.wallpaper = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Generate and set a composited wallpaper on this host.";
    };

    backgroundColor = mkOption {
      type = types.str;
      default = "#252A35";
      description = ''
        ImageMagick-compatible color for the wallpaper background, e.g.
        "#000000" or "black".
      '';
    };

    foregroundImage = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional foreground image (e.g. a ministry/church logo) composited
        centered over the background. Use a PNG with an alpha channel --
        transparent areas let the background color show through. See
        assets/README.md for where to drop this file.
      '';
    };

    foregroundScale = mkOption {
      type = types.float;
      default = 0.45;
      description = ''
        Fraction of the wallpaper's height the foreground image is scaled
        to (aspect ratio preserved), before being centered. 0.45 means the
        logo ends up roughly 45% as tall as the screen.
      '';
    };

    width = mkOption {
      type = types.int;
      default = 2560;
      description = "Wallpaper width in pixels.";
    };

    height = mkOption {
      type = types.int;
      default = 1440;
      description = "Wallpaper height in pixels.";
    };

    font = mkOption {
      type = types.str;
      default = "${pkgs.ubuntu-classic}/share/fonts/truetype/ubuntu/Ubuntu-B.ttf";
      description = ''
        ImageMagick font name for the hostname watermark, or an absolute
        path to a .otf/.ttf file.

        Defaults to Ubuntu Bold, pulled straight from nixpkgs
        (`pkgs.ubuntu-classic`) as a direct file path -- unlike a commercial
        font (e.g. Gotham), this needs nothing installed on the Mac itself;
        Nix fetches and builds it like any other package, so it's always
        there and always the same bits. To use a font name instead of a
        path (e.g. something already installed via Font Book/MDM), just set
        this to a plain string like "Gotham-Bold" -- if ImageMagick can't
        resolve a name, it silently falls back to its own default font
        rather than failing the build, so a bad name won't break
        `darwin-rebuild switch`, it'll just render in the wrong typeface.
      '';
    };

    fontSize = mkOption {
      type = types.int;
      default = 42;
      description = "Point size for the hostname watermark.";
    };

    textColor = mkOption {
      type = types.str;
      default = "white";
      description = "Color of the hostname text.";
    };

    margin = mkOption {
      type = types.int;
      default = 80;
      description = "Pixels of padding from the bottom-left corner to the hostname text.";
    };
  };

  config = mkIf cfg.enable {
    production.macApps.apps = [ "desktoppr" ];

    launchd.user.agents.nc-set-wallpaper = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''test -x /usr/local/bin/desktoppr && exec /usr/local/bin/desktoppr 0 "${wallpaperImage}"''
        ];
        RunAtLoad = true;
        StandardOutPath = "/tmp/nc-set-wallpaper.log";
        StandardErrorPath = "/tmp/nc-set-wallpaper.log";
      };
    };
  };
}
