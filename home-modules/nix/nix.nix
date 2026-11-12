{ lib, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 30d";
  };

  home.packages = [
    pkgs.deadnix
    pkgs.nixfmt
    pkgs.statix
  ];

  xdg.configFile."issl/nix/nix.conf".source = ./nix.conf;

  programs.home-manager.enable = true;
}
