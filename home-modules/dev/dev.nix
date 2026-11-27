{ pkgs, ... }:

{
  home.packages = [
    pkgs.capsula
    pkgs.commitizen
    pkgs.prek
    pkgs.rumdl
    pkgs.tombi
    pkgs.typos
    pkgs.yamllint
  ];
}
