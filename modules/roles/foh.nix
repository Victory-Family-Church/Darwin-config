# Role: Front of House audio computer.
# "FOH needs spotify, wireless workbench, klang, DVS, and dante
# controller. And reaper."
{ lib, ... }:

{
  production.macApps.apps = [
    "spotify"
    "wireless-workbench"
    "klang-fabrik"
    "dante-virtual-soundcard"
    "dante-controller"
    "reaper"
  ];

  # klang-fabrik, dante-virtual-soundcard: packages.json has these as
  # "manual" -- there's no discoverable stable/public download URL (Klang
  # requires an account, DVS requires a purchased Audinate license). Fill
  # in the real URL with:
  #   python3 scripts/update_packages.py --manual klang-fabrik <url>
  #   python3 scripts/update_packages.py --manual dante-virtual-soundcard <url>
  # before the first `darwin-rebuild switch` on this host.
}
