{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.issl.nix.memoryLimit;

  nixMemoryLimitScript =
    builtins.replaceStrings
      [
        "@readlink@"
        "@env@"
        "@sleep@"
        "@grep@"
        "@flock@"
        "@percent@"
        "@nixPackageNix@"
      ]
      [
        "${pkgs.coreutils}/bin/readlink"
        "${pkgs.coreutils}/bin/env"
        "${pkgs.coreutils}/bin/sleep"
        "${pkgs.gnugrep}/bin/grep"
        "${pkgs.util-linux}/bin/flock"
        (toString cfg.percent)
        (lib.optionalString (config.nix.package != null) "${config.nix.package}/bin/nix")
      ]
      (builtins.readFile ./nix-memory-limit.sh);

  nixMemoryLimit =
    assert builtins.length (builtins.split "@[A-Za-z]+@" nixMemoryLimitScript) == 1;
    pkgs.writeShellApplication {
      name = "nix";
      text = nixMemoryLimitScript;
    };
in
{
  options.issl.nix.memoryLimit = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether to run each `nix` command under a memory limit,
        so that an evaluation that outgrows the memory available is stopped
        instead of exhausting the memory of the whole desktop session.
        Limited commands share one limit, so that together they stay within it.
        The wrapper runs the Nix that `nix.package` names when that is set,
        and otherwise the next `nix` on `PATH`, normally the one the host installed.
        The limit applies only where a systemd user session is available,
        and not to `nix develop`, `nix shell`, `nix env shell` and `nix run`,
        whose limit would carry over to the shell or program they start,
        nor to the legacy `nix-*` commands such as `nix-build`.
      '';
    };

    percent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 75;
      example = 50;
      description = ''
        The memory limit that the running limited `nix` commands share,
        as a percentage of the memory available to them, recomputed whenever one starts.
        It is not set below what the commands already running use plus a margin,
        of a tenth of that or 256 MiB, whichever is larger, so they stop only if they grow past it.
      '';
    };
  };

  config = {
    nixpkgs.config.allowUnfree = true;

    nix.gc = {
      automatic = lib.mkDefault true;
      options = lib.mkDefault "--delete-older-than 30d";
    };

    home.packages = [
      pkgs.deadnix
      pkgs.nix-search-cli
      pkgs.nixfmt
      pkgs.statix
    ]
    ++ lib.optional cfg.enable (lib.hiPrio nixMemoryLimit);

    xdg.configFile."issl/nix/nix.conf".source = ./nix.conf;

    programs.home-manager.enable = true;
  };
}
