{ pkgs, ... }:

{
  home.packages = [
    pkgs.commitizen
    pkgs.prek
    pkgs.rumdl
    pkgs.tombi
    pkgs.typos
    pkgs.yamllint
  ];
}
