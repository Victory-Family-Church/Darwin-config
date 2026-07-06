{
  description = "nix-darwin configurations for NC production Mac Minis (CG-1 Main, CG-2 FOH, CG-3 Lighting, NextGen CG-1)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-darwin, ... }@inputs:
    let
      # All three Macs are Apple Silicon (M4) Mac Minis.
      system = "aarch64-darwin";

      # Every host shares the same overlay (adds pkgs.macApps.*) and the
      # same base modules; only the host file + role module differ.
      overlays = [ (import ./overlays/production-apps.nix) ];

      mkHost = { hostName, extraModules ? [ ] }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit inputs hostName; };
          modules = [
            { nixpkgs.overlays = overlays; }
            ./modules/mac-app-activation.nix
            ./modules/wallpaper.nix
            ./modules/common.nix
          ] ++ extraModules;
        };
    in
    {
      darwinConfigurations = {
        # Main worship service presentation computer.
        "NC-Production-Main-CG-1" = mkHost {
          hostName = "NC-Production-Main-CG-1";
          extraModules = [ ./hosts/nc-production-main-cg-1 ];
        };

        # Front of House audio computer (second production Mac for Main).
        "NC-Production-Main-CG-2" = mkHost {
          hostName = "NC-Production-Main-CG-2";
          extraModules = [ ./hosts/nc-production-main-cg-2 ];
        };

        # Student ministry (NextGen) presentation computer.
        "NC-Production-NextGen-CG-1" = mkHost {
          hostName = "NC-Production-NextGen-CG-1";
          extraModules = [ ./hosts/nc-production-nextgen-cg-1 ];
        };

        # Lighting control (grandMA3 onPC) -- third production computer for Main.
        "NC-Production-Main-CG-3" = mkHost {
          hostName = "NC-Production-Main-CG-3";
          extraModules = [ ./hosts/nc-production-main-cg-3 ];
        };
      };
    };
}
