# Repository Structure

This page explains how this repository is organized for development.

## Overview

This repository defines a shared user environment for ISSL with Nix flakes and Home Manager.

At a high level:

- `flake.nix` defines supported systems and Home Manager outputs.
- `home-modules/` defines the shared environment as composable modules, each holding the configuration files it deploys.
- `scripts/` provides imperative entry points for setup and application.
- `tests/` verifies that the resulting environment and deployed files match expectations.
- `docs/` explains usage and maintenance.

## Top-Level Layout

### `flake.nix` and `flake.lock`

- `flake.nix` is the main entry point for the Nix-based configuration.
- It defines:
  - the upstream inputs such as `nixpkgs` and `home-manager`
  - supported systems
  - the shared Home Manager module exported as `homeModules.common`, aliased as `homeModules.default`
  - Home Manager configurations such as `common-x86_64-linux` and its Bash-only variant `common-bash-only-x86_64-linux`
  - basic checks built from those configurations
- `flake.lock` pins dependency revisions for reproducibility.

### `home-modules/`

This directory contains the Home Manager modules that define the shared environment.
Each module is a directory holding its Nix expression together with the configuration files it deploys.

- `<name>/<name>.nix` is the module itself, such as `nix/nix.nix`, `git/git.nix`, or `python/python.nix`.
  - `shell/shell.nix` holds what Bash and Zsh share.
    `bash/bash.nix` and `zsh/zsh.nix` hold what belongs to one shell only.
  - `zsh/zsh.nix` deploys the shared Zsh configuration unless the `issl.zsh.enable` option is set to `false`.
- Every other file in the directory is a configuration file that the module deploys, such as `git/gitconfig` or `python/pythonrc.py`.
- `default.nix` is the aggregation point, and the only `default.nix` in this directory tree.
  It imports every module directory automatically.

### `scripts/`

This directory contains imperative shell entry points.

- `scripts/bootstrap-host.sh` prepares the host for setup: it installs Nix and offers optional login shell registration,
  GitHub SSH access, and Docker Engine setup.
  - The login shell registration points `/etc/passwd` at `~/.local/state/issl/login-shell`,
    the link that `zsh/zsh.nix` deploys and retargets on every switch.
  - `scripts/apply.sh` sources this script and reuses that registration after the switch when Zsh is enabled.
- `scripts/setup.sh` is the script-based setup entry point.
  - It prepares the host for setup through `scripts/bootstrap-host.sh`.
  - It clones this repository into the install location.
  - It is designed for users who start from a plain Linux environment.
- `scripts/apply.sh` applies this repository's shared configuration into the current user environment.
  - It writes include blocks or startup hooks into user-controlled files.
  - It places the shared configuration files under the ISSL config directory.

### `tests/`

This directory contains shell-based validation scripts for each area of the environment.

- `lib.sh` provides the shared test helpers, such as assertions, test logging and failure reporting.
  Every `test-*.sh` sources it.
- `run.sh` runs all the test scripts in order.
- Each `test-*.sh` corresponds to the module of the same name, such as:
  - `test-shell.sh` checks the shared shell files and startup file integration.
  - `test-git.sh` checks Git installation and global include behavior.
  - `test-dev.sh` checks installation of the language-agnostic development tools.
  - `test-python.sh` checks tool installation and shared config wiring.
- `pty-driver.py` drives an interactive Python REPL under a PTY for `test-python.sh`.

These tests verify that the expected tools are available
and that the files each module deploys are installed and referenced correctly.
In GitHub Actions they run from two places.
The script-based setup is exercised by the `script-based` job of `.github/workflows/test.yaml`,
which has only this repository as its caller and therefore lives inline.
The config-repository-based setup is exercised by the reusable `.github/workflows/test-config-repository.yaml`,
which applies one flake target of one personal config repository and then runs these tests against the result.
Every axis it is tested over — the OS, the flake target — belongs to the matrix of the calling workflow,
so this repository, the template, and each personal config repository decide their own coverage.

### `docs/`

This directory contains user-facing and developer-facing documentation.
