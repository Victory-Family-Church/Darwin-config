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

      # Plain nixpkgs import (not darwinSystem) for flake-level packages/apps
      # like provision-vendor below, which don't need a whole darwin config.
      pkgsFor = import nixpkgs { inherit system; inherit overlays; };

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

      # `nix build .#provision-vendor` / `nix run .#provision-vendor -- --staging ~/Downloads`.
      # One-time setup helper: copies manual-local/"external" vendor
      # installers (grandMA3 onPC, Blackmagic Desktop Video/ATEM Software
      # Control, Dante Virtual Soundcard, Spotify -- all too large or too
      # access-gated to fetch or commit to git, see vendor/README.md) into
      # their fixed system paths and verifies each against packages.json's
      # localSha256. Deliberately a thin wrapper around
      # scripts/update_packages.py provision rather than its own
      # implementation -- one source of truth for the provisioning logic.
      #
      # Uses $PWD (resolved by bash when you actually run it), not a Nix
      # path, to find scripts/update_packages.py -- interpolating a Nix
      # path here would copy it into the read-only /nix/store, severing it
      # from the live packages.json sitting next to it in your checkout
      # (same bug class fixed in shell.nix earlier). Run this from the
      # repo root, same as `update-packages` in shell.nix.
      packages.${system}.provision-vendor = pkgsFor.writeShellApplication {
        name = "provision-vendor";
        runtimeInputs = [ pkgsFor.python3 ];
        text = ''
          exec python3 "$PWD/scripts/update_packages.py" provision "$@"
        '';
      };

      apps.${system}.provision-vendor = {
        type = "app";
        program = "${self.packages.${system}.provision-vendor}/bin/provision-vendor";
      };
    };
}
