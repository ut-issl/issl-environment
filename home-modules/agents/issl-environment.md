# ISSL Environment

This machine uses the [ISSL shared environment](https://github.com/ut-issl/issl-environment),
which manages the user environment with Nix and Home Manager.
Follow these practices when installing software or adding dependencies.

## Tools for the Whole User Environment

Install a tool that should be available outside a single repository with Nix.
The user applies the shared environment in one of two ways, and a tool is added differently in each:

- **With a personal config repository**: a Git repository of the user,
  created from [`ut-issl/personal-nix-config-template`](https://github.com/ut-issl/personal-nix-config-template),
  that imports the shared environment as a flake input.
  Add the package to a module under its `home-modules/`, and apply it as its README describes.
  The repository ships a `customize` skill for this.
- **With the script-based setup**: the shared environment is applied from its clone,
  `~/.local/share/issl/environment` by default.
  Install the tool with `nix profile add nixpkgs#<package>`.
  A package with an unfree license needs `NIXPKGS_ALLOW_UNFREE=1 nix profile add --impure nixpkgs#<package>`.

If it is unclear which one applies, or where the personal config repository is, ask the user.

Do not install such a tool with `pip`, `pipx`, `uv tool install`, `npm install -g`, `cargo install`, or `cargo binstall`.

## Dependencies of a Repository

Manage the dependencies of a repository with the package manager of its language:

- Python: `uv` with `pyproject.toml`, such as `uv add` and `uv run`. Do not use `pip`, `pipx`, or `poetry`.
- Rust: `rustup` with `rust-toolchain.toml` for the toolchain, and `cargo add` for crates.
- Node.js: `npm` with `package.json`.

## Distribution Packages

Use the package manager of the distribution, such as `apt`, only for what the distribution has to own:
services, drivers, and low-level OS packages;
applications that depend on the sandboxing rules, input methods, or device permissions of the distribution;
and applications that refuse to run until they are updated.
