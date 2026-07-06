# NC-Production-Main-CG-1 -- main worship service presentation Mac Mini (M4).
{ ... }:

{
  imports = [
    ../../modules/roles/main-presentation.nix
    (import ../../modules/cg-account.nix { username = "CG-1"; uid = 501; })
  ];
}
