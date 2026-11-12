{ pkgs, ... }:

{
  home.packages = [
    pkgs.uv
    pkgs.ruff
  ];

  xdg.configFile."issl/python/pythonrc.py".source = ./pythonrc.py;
}
