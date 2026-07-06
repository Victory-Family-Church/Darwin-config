# NC-Production-NextGen-CG-1 -- Student ministry (SA) presentation Mac Mini (M4).
{ ... }:

{
  imports = [
    ../../modules/roles/nextgen-presentation.nix
    (import ../../modules/cg-account.nix { username = "CG-1"; uid = 501; })
  ];
}
