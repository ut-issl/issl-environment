# Setup with a Personal Config Repository

This guide covers the workflow of maintaining a personal Nix configuration repository with Home Manager
that imports this repository.

## What This Path Gives You

Your own repository describes your whole user environment as code:
the shared ISSL environment this repository provides, and your personal tools and settings on top of it.
Applying it on another machine reproduces that environment,
and every change to it is reviewable and revertible like any other code.

Choose this path if you want personal customization with reproducibility across machines and reinstallations,
and are willing to maintain a repository of your own.
If the shared environment is mostly sufficient and extra tools are occasional,
[script-based setup](12-script-based-setup.md) is the lighter choice.

## How the Repositories Relate

Three repositories are involved:

- **This repository** provides the shared ISSL environment as a Home Manager module.
  A personal config repository consumes it as a flake input pinned to a release tag.
- **[`ut-issl/personal-nix-config-template`](https://github.com/ut-issl/personal-nix-config-template)**
  is the starting point: a personal config repository that already imports this repository,
  with the scaffolding and the agent skills in place.
- **Your own repository**, created from that template, is yours to change.

## Getting Started

Create your repository from the template with the **Use this template** button on GitHub,
then follow the Getting Started section of its README.

The section's first step runs `bootstrap-host.sh` from a release of this repository.
The script installs Nix, starts `nix-daemon` on systems without systemd,
and offers to set up GitHub SSH access and the host Docker Engine.
It is the only part of the setup that needs privileges, and it is the same script the [script-based setup](12-script-based-setup.md) runs.

## What the Shared Configuration Provides

A personal config repository imports the Home Manager module this repository exports,
named `homeModules.common` and aliased as `homeModules.default`.

These options are yours to set:

- `issl.zsh.enable` (default: `true`) installs and configures Zsh.
  Set it to `false` for a Bash-only environment; the shared Bash configuration applies either way.
- `targets.genericLinux.gpu.enable` (default: `false`) turns on the GPU driver integration
  that Nix-built applications rendering through OpenGL need, and asks for a one-time privileged setup on each machine.
  See [package management practices](13-package-management-practices.md#gui-applications).
- `nix.gc.automatic` (default: `true`) runs the Nix garbage collector once a week through a systemd user timer,
  with the options in `nix.gc.options` (default: `--delete-older-than 30d`).
  It does not run on a host without a systemd user session.
  Each run deletes the generations of your profiles that are older than 30 days, except the most recent of them,
  so you can still roll back to any state from the last 30 days.

The shared module also decides the following for every configuration that imports it:

- Shared configuration files are deployed under `~/.config/issl`,
  for the personal modules to source or include them from the files Home Manager manages.
- `nixpkgs.config.allowUnfree` is set to `true`,
  so unfree packages you add in your own repository install without extra setup.
  See [package management practices](13-package-management-practices.md#unfree-packages).
- Clients that a remote service refuses once they fall too far behind, such as Codex and Claude Code,
  come from `nixpkgs-unstable` instead of the stable release, including when you install one in your own repository.
- `targets.genericLinux` is enabled, so the desktop entries of the packages you install are visible to the desktop environment.
- Your login shell follows `issl.zsh.enable`,
  through the link `~/.local/state/issl/login-shell` that the shared module retargets on every switch.
  `bootstrap-host.sh` registers that link in `/etc/passwd` once, because Home Manager cannot edit `/etc/passwd` itself.
  If you decline that step, a switch with Zsh enabled tells you the command that hands the login shell over.

This repository also exports the reusable workflow `.github/workflows/test-config-repository.yaml`.
It applies one flake target of a personal config repository and runs the environment tests against the result.
Every axis the tests run over is an input, so each repository decides its own coverage:
`flake-target` selects the configuration to apply, `zsh-enabled` tells the tests which shell to expect,
and `os` selects the runner.

## Keeping Up to Date

Updates reach your repository through two routes:

- **Releases of this repository** arrive when you point your flake input at a newer release tag,
  by hand or through Renovate if you enable it.
  A release that requires a change on your side says so in its notes.
- **Improvements to the template** arrive through its [`sync-template` agent skill](https://github.com/ut-issl/personal-nix-config-template#sync-template),
  which merges the template's later commits into your repository and opens a pull request.

Taking a new release of this repository does not require a sync with the template.
A sync usually brings a newer release with it, however: the template pins this repository too,
so its commits include the bump and any change the release called for.

## Migrating from the Script-Based Setup

Moving from [script-based setup](12-script-based-setup.md) to your own repository does not need a fresh machine.

### 1. Set Up Your Repository

Create your repository as described in [Getting Started](#getting-started),
and follow its README up to, but not including,
[Apply the Configuration](https://github.com/ut-issl/personal-nix-config-template#4-apply-the-configuration).
Nix is already installed, so its bootstrap step skips the installation.
It asks again about the login shell and GitHub SSH access if you turned them down before,
and about Docker Engine in any case, so accept what you need now.

If you ran the script-based setup with Zsh turned off,
make your repository Bash-only as described in [Choose Your Shell](https://github.com/ut-issl/personal-nix-config-template#choose-your-shell).
Otherwise your configuration turns Zsh on, and your login shell switches to it if Home Manager manages your login shell.

For [Configure Your Git Identity](https://github.com/ut-issl/personal-nix-config-template#3-configure-your-git-identity),
reuse the identity that the setup script configured.
These commands print the name and email to put in `home-modules/git/git.nix`:

```sh
git config --global user.name
git config --global user.email
```

If either prints nothing, the setup script ran without an identity.
Choose one now, and also set it with `git config --global` so that you can commit before the first switch:

```sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

### 2. Move Your Packages

List the packages you installed imperatively:

```sh
nix profile list
```

Add each of them to `home.packages` in your own modules,
then remove it from the profile so that Home Manager can install it without a conflict:

```sh
nix profile remove <name>
```

The removed packages stay unavailable until you apply your configuration.
Leave the `home-manager-path` entry in place:
it holds the shared environment, which your configuration replaces when you apply it.

Commit these changes before you apply them.
A flake only sees files tracked by Git, so a new module left untracked would be skipped without an error.

### 3. Apply Your Configuration

Run the first `home-manager switch` command in
[Apply the Configuration](https://github.com/ut-issl/personal-nix-config-template#4-apply-the-configuration)
with `-b pre-migration` appended.
The setup script wrote configuration files that your configuration now manages,
such as `~/.config/nix/nix.conf`, `~/.config/python/pythonrc.py`, and `~/.cargo/config.toml`,
and Home Manager refuses to replace them.
The option moves each of them to `<file>.pre-migration`,
together with `~/.bashrc` and the other shell startup files that your configuration would otherwise overwrite.
Do not use `backup` as the extension:
the setup script keeps the files it replaced at `<file>.backup`, and Home Manager would silently overwrite them.

### 4. Carry Over Your Remaining Settings

The script-based setup leaves these files behind, where present:

- the `.pre-migration` files from the previous step
- `~/.profile.backup` and `~/.bashrc.backup`, which hold what those files contained before the setup script replaced them
- `~/.gitconfig`, which holds the Git settings made with `git config --global`,
  including the shared include that your configuration already provides

Before you carry anything over, rename `~/.gitconfig` to `~/.gitconfig.pre-migration`.
Git reads it after the `~/.config/git/config` that your configuration manages,
so while it is in place, its values take precedence over yours and hide any setting you have not carried over:

```sh
mv ~/.gitconfig ~/.gitconfig.pre-migration
```

Carry anything you still want from these files over to your own modules,
as described in [Customize Your Configuration](https://github.com/ut-issl/personal-nix-config-template#customize-your-configuration),
then commit it and re-apply your configuration as described in [Apply Your Changes](https://github.com/ut-issl/personal-nix-config-template#apply-your-changes).
Once your settings work as before, delete these files, including `~/.gitconfig.pre-migration`.

The clone that the setup script made is no longer applied once your own configuration takes over.
Remove it when nothing else refers to it; unless `INSTALL_DIR` was set, it is at `${XDG_DATA_HOME:-$HOME/.local/share}/issl/environment`.
