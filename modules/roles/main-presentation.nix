# Role: main worship service presentation computer (CG-1).
# "CG-1 only needs propresenter and decklink, and word and powerpoint."
# Decklink support == Blackmagic Desktop Video, which every host already
# gets from modules/common.nix.
{ lib, ... }:

{
  production.macApps.apps = [
    "propresenter"
    "microsoft-word"
    "microsoft-powerpoint"
  ];

  # "It also should be signed into main pro in the Mail app."
  # Nix/nix-darwin deliberately can't script signing into a mail account --
  # that flow lives in Keychain/Internet Accounts and needs an interactive
  # password (or an app-specific/OAuth token) entered by a human. Do this
  # once by hand after first login: Mail > Settings > Accounts > Add
  # Account, using the "Main Pro" credentials.
}
