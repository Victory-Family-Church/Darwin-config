# Role: Front of House audio computer.
# "FOH needs spotify, wireless workbench, klang, DVS, and dante
# controller. And reaper."
{ lib, ... }:

{
  production.macApps.apps = [
    "spotify"
    "wireless-workbench"
    "klang-app"
    "dante-virtual-soundcard"
    "dante-controller"
    "reaper"
  ];

  # spotify, dante-virtual-soundcard: both "manual-local" in packages.json
  # -- checked into vendor/ instead of fetched (Spotify: pinned to a known
  # build on purpose instead of always tracking whatever's currently live;
  # DVS: no public download URL, requires a purchased Audinate license).
  # Before the first `darwin-rebuild switch` on this host:
  #   1. save the installer at vendor/spotify.dmg / vendor/dante-virtual-soundcard.pkg
  #   2. git add it
  #   3. python3 scripts/update_packages.py pkg update spotify <version>
  #      python3 scripts/update_packages.py pkg update dante-virtual-soundcard <version>
  # See vendor/README.md.
  #
  # klang-app (KLANG:app) turned out to have a plain, stable download URL
  # once we actually looked -- no manual step needed, see packages.json.
}
