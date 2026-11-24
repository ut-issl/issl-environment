{ pkgs, ... }:

{
  home.packages = [
    pkgs.curl
    pkgs.fd
    pkgs.jq
    pkgs.poppler-utils
    pkgs.ripgrep
    pkgs.tree
    pkgs.wget
  ];
}
