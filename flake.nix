{
  description = "Shared ISSL environment built with Nix and Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs { inherit system; };
      homeModules = rec {
        common = {
          imports = [ ./home-modules ];
          _module.args.nixpkgsUnstable = nixpkgs-unstable;
        };
        default = common;
      };
      requireEnv =
        name:
        let
          value = builtins.getEnv name;
        in
        if value != "" then
          value
        else
          throw "Environment variable ${name} is required. Run Home Manager with --impure.";
      mkHomeConfiguration =
        {
          system,
          username ? requireEnv "USER",
          homeDirectory ? requireEnv "HOME",
          enableZsh ? true,
        }:
        let
          pkgs = mkPkgs system;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            homeModules.default
          ]
          ++ [
            {
              issl.zsh.enable = enableZsh;
              home = {
                inherit username homeDirectory;
                stateVersion = "26.05";
              };
            }
          ];
        };
    in
    {
      packages = forAllSystems (system: {
        default = home-manager.packages.${system}.home-manager;
        inherit (home-manager.packages.${system}) home-manager;
      });

      inherit homeModules;

      homeConfigurations = {
        common-x86_64-linux = mkHomeConfiguration {
          system = "x86_64-linux";
          enableZsh = true;
        };
        common-aarch64-linux = mkHomeConfiguration {
          system = "aarch64-linux";
          enableZsh = true;
        };
        common-bash-only-x86_64-linux = mkHomeConfiguration {
          system = "x86_64-linux";
          enableZsh = false;
        };
        common-bash-only-aarch64-linux = mkHomeConfiguration {
          system = "aarch64-linux";
          enableZsh = false;
        };
      };

      formatter = forAllSystems (system: (mkPkgs system).nixfmt);

      checks = forAllSystems (system: {
        home =
          (mkHomeConfiguration {
            inherit system;
            username = "issl";
            homeDirectory = "/tmp/issl-home";
            enableZsh = true;
          }).activationPackage;
        home-bash-only =
          (mkHomeConfiguration {
            inherit system;
            username = "issl";
            homeDirectory = "/tmp/issl-home";
            enableZsh = false;
          }).activationPackage;
        gpu-opt-in =
          let
            cfg =
              (mkHomeConfiguration {
                inherit system;
                username = "issl";
                homeDirectory = "/tmp/issl-home";
              }).config;
          in
          assert nixpkgs.lib.assertMsg (!cfg.targets.genericLinux.gpu.enable)
            "targets.genericLinux.gpu.enable must stay off in the shared environment: enabling it asks every host for a privileged one-time setup.";
          (mkPkgs system).emptyFile;
        unstable-packages =
          let
            home = mkHomeConfiguration {
              inherit system;
              username = "issl";
              homeDirectory = "/tmp/issl-home";
            };
            unstablePkgs = import nixpkgs-unstable {
              inherit system;
              config.allowUnfree = true;
            };
            notFromUnstable =
              builtins.filter (name: home.pkgs.${name}.outPath != unstablePkgs.${name}.outPath)
                [
                  "claude-code"
                  "codex"
                ];
          in
          assert nixpkgs.lib.assertMsg (notFromUnstable == [ ])
            "${nixpkgs.lib.concatStringsSep ", " notFromUnstable} must come from nixpkgs-unstable: an outdated client can be refused by its remote service.";
          (mkPkgs system).emptyFile;
      });
    };
}
