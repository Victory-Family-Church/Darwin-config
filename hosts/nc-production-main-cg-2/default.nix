# NC-Production-Main-CG-2 -- Front of House audio Mac Mini (M4).
# Second production computer for Main, hence "-CG-2" (CG-1 is the
# presentation computer defined in ../nc-production-main-cg-1).
{ ... }:

{
  imports = [
    ../../modules/roles/foh.nix
    (import ../../modules/cg-account.nix { username = "CG-2"; uid = 501; })
  ];
}
