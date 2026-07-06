# NC-Production-Main-CG-3 -- lighting control Mac Mini (M4).
# Third production computer for Main (CG-1 = presentation, CG-2 = FOH,
# CG-3 = lighting / grandMA3 onPC).
{ ... }:

{
  imports = [
    ../../modules/roles/lighting.nix
    (import ../../modules/cg-account.nix { username = "CG-3"; uid = 501; })
  ];
}
