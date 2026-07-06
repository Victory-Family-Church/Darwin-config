{ config, lib, pkgs, hostName, ... }:

# Shared baseline for every NC production Mac Mini. Host-specific files
# under hosts/<name>/default.nix import this indirectly via flake.nix and
# layer their role module + user account on top.

let
  logoPath = ../assets/logo.png;
  hasLogo = builtins.pathExists logoPath;
in

{
  networking.hostName = hostName;
  networking.localHostName = hostName;
  networking.computerName = hostName;

  # Solid black wallpaper + hostname watermark on every host (see
  # modules/wallpaper.nix). If assets/logo.png exists, composite it in too --
  # see assets/README.md.
  production.wallpaper = lib.mkIf hasLogo {
    foregroundImage = logoPath;
  };

  # Each host module (hosts/<name>/default.nix) sets
  # `system.primaryUser = "<its CG account>";` -- nix-darwin needs this
  # once anything touches per-user `system.defaults.*` domains, which the
  # autologin setting in each host file does.

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "@admin" ];

  # Bump only after reading the nix-darwin release notes for the version
  # you actually pin in flake.lock.
  system.stateVersion = 5;

  # ---- Apps every NC production Mac gets, regardless of role ----
  # Dropbox: "and dropbox on all computers"
  # Tailscale: fleet-wide remote admin VPN
  # TeamViewer: ad-hoc remote support
  # Blackmagic Desktop Video + ATEM Software Control: "all configurations
  #   need blackmagic desktop video and blackmagic atem controller"
  production.macApps.apps = [
    "dropbox"
    "tailscale"
    "teamviewer"
    "blackmagic-desktop-video"
    "atem-software-control"
  ];

  environment.systemPackages = [ pkgs.vim ];

  system.defaults.loginwindow.GuestEnabled = false;

  # Minimal dock everywhere -- no pinned apps, no "recent applications"
  # clutter. Finder/Trash still show (macOS always keeps those); everything
  # else that's actually running still appears while it's running, it just
  # doesn't stay pinned afterward.
  system.defaults.dock = {
    persistent-apps = [ ];
    persistent-others = [ ];
    show-recents = false;
  };
}
