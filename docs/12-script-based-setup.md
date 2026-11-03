# Script-Based Setup

This guide covers the workflow of setting up the shared environment with the setup script provided by this repository.

## What This Path Gives You

The setup script applies the shared ISSL environment to your user account in one run.
There is no repository of your own to create or maintain.
This path assumes the shared environment is mostly sufficient, and that installing an extra tool is an occasional need.

Choose this path for a shared PC, or when you do not need your personal customization to be reproducible.
If you want your own tools and settings versioned and restored on any machine,
[setup with a personal config repository](11-setup-with-a-personal-config-repository.md) is the better fit.

## Getting Started

> [!CAUTION]
> The first run **replaces** the two startup files that Ubuntu seeds from `/etc/skel`: `~/.profile` and `~/.bashrc`.
>
> On a fresh Ubuntu account these are just the default skeleton files,
> so there is nothing of yours to lose and you can safely proceed.
>
> If you have customized either of them, the previous file is kept at `<file>.backup`,
> so you can merge what you want to keep back into the new file afterwards.
> Later runs leave these files alone, so your own edits survive from then on.

Run:

```bash
bash <(curl -fsSL https://github.com/ut-issl/issl-environment/releases/latest/download/setup.sh)
```

To pin setup to a fixed release, replace `latest` with a tag such as `v0.8.11`:

```bash
bash <(curl -fsSL https://github.com/ut-issl/issl-environment/releases/download/v0.8.11/setup.sh)
```

Each release's `setup.sh` defaults to installing that same release,
so pinning the download tag also pins the installed environment.

To override setup variables, set environment variables before running the command.
For example, set `REPO_REF=main` for development, or set `INSTALL_DIR` to choose another install location:

```bash
INSTALL_DIR="$HOME/.issl-environment" \
bash <(curl -fsSL https://github.com/ut-issl/issl-environment/releases/latest/download/setup.sh)
```

After setup, open a new shell.

### Repository Overrides

Set `REPO_URL` and `REPO_REF` to install from another GitHub repository or ref.
For streamed setup, bootstrap script selection has the following limits:

- HTTPS public forks and mirrors are supported.
- SSH private repositories can be used as the install target,
  but `bootstrap-host.sh` is downloaded from the public shared repository.
- Private fork-specific `bootstrap-host.sh` files are not supported by streamed setup.
- To use a private fork-specific bootstrap script, clone the repository first and run its local `scripts/setup.sh`.

### Optional Docker Engine Setup

The shared Home Manager configuration installs the Docker CLI tools.
Interactive setup prompts to install the host Docker Engine with yes as the default answer.
Non-interactive setup skips Docker Engine unless you opt in explicitly:

```bash
ISSL_INSTALL_DOCKER=yes \
bash <(curl -fsSL https://github.com/ut-issl/issl-environment/releases/latest/download/setup.sh)
```

Set `ISSL_INSTALL_DOCKER=no` to skip the prompt explicitly.

### Login Shell

Setup asks, with yes as the default answer, to make `~/.local/state/issl/login-shell` your login shell.
That link is registered in `/etc/passwd` once and retargeted by every later switch,
so the login shell follows whether Zsh is enabled instead of needing `chsh` again.
Non-interactive setup cannot ask and leaves the login shell alone.

Declining leaves your login shell as it is; while Zsh is enabled, a later switch tells you the command that hands it over.

### Zsh in a Non-Interactive Setup

Zsh is enabled without asking when it is already your login shell.
Otherwise interactive setup asks, with yes as the default answer,
so nothing has to be set and this section does not concern the usual setup.

Non-interactive setup cannot ask, so it skips Zsh unless you say so:

```bash
ISSL_ENABLE_ZSH=yes \
bash <(curl -fsSL https://github.com/ut-issl/issl-environment/releases/latest/download/setup.sh)
```

## If You Need Additional Tools or Settings

If you later need something more than the shared environment provides, choose one of the following paths.

### 1. If it should be shared within ISSL

If the tool or setting should be part of the standard ISSL environment, reflect it in this repository.
Open a pull request, or contact the maintainers if you are not going to prepare the change yourself.

### 2. If it is personal, but you want reproducibility

If the tool or setting is only for your own use, but you still want to restore it across machines or after reinstallation,
move to a personal Nix configuration repository with Home Manager.

Nix is already installed, and the packages you added with `nix profile` can be carried over.
See [the migration steps](11-setup-with-a-personal-config-repository.md#migrating-from-the-script-based-setup).

### 3. If it is personal, and reproducibility is not necessary

If you just want to try additional tools without moving to a personal config repository yet, use `nix profile`.

Install a package:

```sh
nix profile add nixpkgs#pandoc
```

Install multiple packages:

```sh
nix profile add nixpkgs#elan nixpkgs#quint nixpkgs#z3
```

List installed profile packages:

```sh
nix profile list
```

Remove a package:

```sh
nix profile remove pandoc
```

Upgrade installed profile packages:

```sh
nix profile upgrade --all
```

`nix profile` refuses packages with an unfree license, even though the shared Home Manager configuration allows them.
Allow it for every invocation that evaluates such a package, including a later `nix profile upgrade`:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix profile add --impure nixpkgs#claude-code
```

See [package management practices](13-package-management-practices.md#unfree-packages).
