# Parameterized "CG-*" local account, mirroring the naming style already
# used on CG-1 at Cranberry (account name matches the display/hostname
# case, e.g. "CG-1", "CG-2"). Import this per-host with the right username:
#
#   imports = [ (import ../../modules/cg-account.nix { username = "CG-1"; uid = 501; }) ];
#
{ username, uid, fullName ? username }:
{ config, lib, pkgs, ... }:

{
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    description = fullName;
    uid = uid;
    shell = pkgs.zsh;
    # nix-darwin will create this account on first `darwin-rebuild switch`
    # if it doesn't already exist. It is NOT able to set a login password
    # (no plaintext secrets in the Nix store) -- set one by hand once via
    # System Settings > Users & Groups, or `sudo passwd ${username}`.
    isHidden = false;
  };

  # Admin + autologin (per setup decision). If `isAdminUser` isn't
  # recognized by the nix-darwin release pinned in flake.lock, add the
  # account to the admin group manually instead:
  #   sudo dseditgroup -o edit -a ${username} -t user admin
  users.users.${username}.isAdminUser = true;

  system.primaryUser = username;

  # Autologin also requires the account to have a password already set
  # (see note above) -- macOS stores the autologin secret via its own
  # secure mechanism, not through this config, so expect to flip
  # System Settings > Login Window > "Automatically log in as" once by
  # hand the first time if this option doesn't take effect on its own.
  system.defaults.loginwindow.autoLoginUser = username;
}
