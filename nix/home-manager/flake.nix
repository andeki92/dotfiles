{
    description = "Home Manager flake";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";
    };

    outputs = inputs@{ nixpkgs, home-manager, ... }: let
        system = "x86_64-linux";
        username = "andeki";
    in {
        homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
            pkgs = nixpkgs.legacyPackages.${system};
            modules = [
                ../home.nix
                {
                    home = {
                        inherit username;
                        homeDirectory = "/home/${username}";
                         stateVersion = "24.05";
                    };
                }
            ];
        };
    };
}