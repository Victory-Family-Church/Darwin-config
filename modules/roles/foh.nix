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

  # dante-virtual-soundcard: packages.json has this as "manual" -- DVS
  # requires a purchased Audinate license, so there's no public download
  # URL to poll. Fill in the real URL with:
  #   python3 scripts/update_packages.py pkg update dante-virtual-soundcard <url>
  # before the first `darwin-rebuild switch` on this host.
  #
  # klang-app (KLANG:app) turned out to have a plain, stable download URL
  # once we actually looked -- no manual step needed, see packages.json.
}
