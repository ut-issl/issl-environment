{ pkgs, ... }:

{
  home.packages = [
    pkgs.gh
    pkgs.act
    pkgs.actionlint
    pkgs.zizmor
  ];
}
