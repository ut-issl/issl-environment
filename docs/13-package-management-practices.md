# Package Management Practices

This page describes the recommended practices for package management after setup.

When choosing how to install tools after setup, use this order by default:

1. Nix with Home Manager for globally available user-environment tools.
2. Project-local package managers (`uv`, `cargo`, `npm`, etc.) for repository-specific dependencies.
3. The distribution's package manager, such as `apt`,
   when the package has to be owned by the distribution: system-level or host integration,
   or applications that enforce their own updates.

Coding agents receive these practices as well, as [coding agents](14-coding-agents.md) describes.

## 1. Globally Available Tools

Use Nix with Home Manager for tools that should be available across your user environment.

- For a personal reproducible setup, see [setup with a personal config repository](11-setup-with-a-personal-config-repository.md).
- For the script-based setup workflow, see [script-based setup](12-script-based-setup.md#if-you-need-additional-tools-or-settings).

### GUI Applications

This environment enables `targets.genericLinux`,
so the desktop entries of the packages it installs are picked up by the desktop environment through `XDG_DATA_DIRS`.

GPU driver integration is disabled here.
A Nix-built application that renders through OpenGL looks for the drivers under `/run/opengl-driver`,
which distributions other than NixOS, such as Ubuntu, do not provide,
so it cannot use the GPU until the integration is set up.

If you install such an application through a personal config repository, enable the integration there:

```nix
targets.genericLinux.gpu.enable = true;
```

The next `home-manager switch` then prints a `sudo` command to run once per machine.

Applications the desktop already provides, such as the browser and the mail client, are best left as they are.
On Ubuntu they are usually snaps that update far faster than a pinned flake,
and a second copy installed through Nix keeps its own profile and adds a duplicate entry to the application list.

See [Distribution Packages](#3-distribution-packages) for the other cases that are better left to the distribution.

### Unfree Packages

This environment sets `nixpkgs.config.allowUnfree = true`, so packages with an unfree license install without extra setup.
This applies both to the shared packages of this repository
and to the packages you add in a personal config repository that imports it.

Installing such a package means accepting its license, which is not the same as the license of this repository.
Check the terms of the package before you install it, and before you propose adding one to the shared environment.

The setting only covers Home Manager.
`nix profile` evaluates Nixpkgs on its own and still refuses unfree packages, as described in [script-based setup](12-script-based-setup.md#3-if-it-is-personal-and-reproducibility-is-not-necessary).

## 2. Project-Local Dependencies

Use project-local package managers for dependencies that belong to a specific repository.

### Rust

- `rustup` is available through this environment.
- Manage project-local Rust toolchains with `rustup`, and define them with `rust-toolchain.toml` in each repository.
- Install globally available Rust tools with Nix/Home Manager instead of `cargo install` or `cargo binstall`.

### Python

- `uv` is available through this environment.
- Manage project-local Python environments with `uv`, and define them in `pyproject.toml` in each repository.
- Do not use other Python package and tool managers such as `pip`, `pipx`, or `poetry`.
- Install globally available Python tools with Nix/Home Manager instead of `uv tool install`.

### Node.js

- `node`, `npm`, and `npx` are available through this environment.
- Manage project-local JavaScript dependencies with `npm`, and define them with `package.json` in each repository.
- Install globally available user-environment tools with Nix/Home Manager instead of `npm install -g`.

## 3. Distribution Packages

Use the distribution's package manager, such as `apt`,
when a package should be owned by the distribution rather than by Home Manager.

- **System-level integration**: services, drivers, and low-level OS packages.
- **Host integration**: applications that depend on the sandboxing rules, input methods, or device permissions of the distribution.
  A package installed under `/nix/store` sits outside those and often loses them.
- **Self-enforcing updates**: applications that refuse to run until they are updated.
  A pinned version stops working before the next `nix flake update`.
