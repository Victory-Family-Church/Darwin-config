# Role: lighting control computer (Main service).
# "the lighting mac needs https://www.malighting.com/downloads/ installed on it"
# -> grandMA3 onPC (confirmed product line).
{ lib, ... }:

{
  production.macApps.apps = [
    "grandma3-onpc"
  ];

  # grandma3-onpc ships as a "manual" package in packages.json -- malighting.com's
  # download area has no stable/versioned URL to poll and may be account-gated.
  # Download it once by hand, then:
  #   python3 scripts/update_packages.py pkg update grandma3-onpc <url>
}
