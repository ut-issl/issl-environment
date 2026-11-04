# Updating or Adding a Module

This page explains the usual workflow for updating or adding a shared module in this repository.

## Agent Skill

This repository ships a `develop` skill for coding agents that support [Agent Skills](https://agentskills.io) (e.g. Codex or Claude Code).
Invoke it with `$develop` in Codex or `/develop` in Claude Code.

It assists the workflow on this page interactively — from checking what already exists and researching Nixpkgs
to editing the modules, extending the tests, and validating the result.
State what you want when invoking it (e.g. `$develop add lazygit`).

It leaves every change uncommitted, so you review the result before committing it yourself.

## What Belongs in the Shared Environment

Everything this repository installs or deploys reaches every machine that applies the shared environment,
so a change belongs here only when it should hold for everyone.
Three destinations are available, and the choice between them comes before any of the work below:

- this repository, for what the whole laboratory should share
- a personal config repository, for what one person wants on their own machines
- the distribution, for what needs host integration that a Nix build cannot keep

[Package management practices](13-package-management-practices.md) describes the last two from the user's side.

The shared environment owns what it deploys under `~/.config/issl/` and `~/.local/state/issl/`,
along with the fixed paths outside them that a module deploys:
`~/.clang-format`, and the files that `agents/agents.nix` adds to the directories coding agents read,
each named after ISSL so that it sits beside the files of the user.
It never takes ownership of a file the user is expected to edit, such as `~/.bashrc` or `~/.config/git/config`.
That rules out `home.file` on such a path, and the `programs.<tool>` options that write one;
a `programs.<tool>` option that only installs a package is unaffected, as `programs.home-manager` in `nix/nix.nix` shows.
[Connecting to User-Managed Files](#connecting-to-user-managed-files) describes how the two are joined instead.

The shared environment installs no graphical application, and a new one does not belong here either.
A Nix build often loses host integration that the package of the distribution keeps, in ways that vary by toolkit.
An AppArmor profile attaches to an executable path.
A Chromium- or Electron-based application built by Nix never matches the profile that grants it a user namespace,
so it fails to start on Ubuntu 24.04 and later, where unprivileged user namespaces are restricted by default.
The IBus input methods do not reach a Nix-built GTK3 application,
and OpenGL rendering needs `targets.genericLinux.gpu.enable`, which is off here.
Where such an application belongs instead depends on the host integration it needs.

`nix/nix.nix` sets `nixpkgs.config.allowUnfree = true` for the whole configuration,
so a module may add a package with an unfree license.
Because that setting also applies to everyone who imports this repository,
state in the pull request why the package is worth distributing to all users under its license terms.

## Changing a Deployed File

A module deploys configuration files from its own directory, so changing what one of them contains needs no change to Nix.

Typical examples are:

- a change to the contents of a shared configuration file
- an updated formatter or editor setting
- a new snippet in an existing startup file

When changing a deployed file:

1. Edit the file in the directory of the module that deploys it, such as `git/gitconfig` or `shell/rc.sh`.
2. Extend the tests under `tests/` if the change adds behavior worth checking.

## Adding a Deployed File

A file that the environment should deploy lives in the directory of the module that deploys it,
and the module names it in a `source` assignment:

```nix
_:

{
  home.file.".foorc".source = ./foorc;
  xdg.configFile."issl/foo/config.toml".source = ./config.toml;
}
```

If the behavior can be expressed directly in Home Manager,
without introducing a separate shared file, a new file is not always necessary.

`xdg.configFile."issl/..."` is the usual destination, under `~/.config/issl/`.
A path the environment maintains rather than the user edits belongs under `~/.local/state/issl/`,
deployed through `xdg.stateFile` as `zsh/zsh.nix` does for the login shell link.
Use `home.file` when the file must live at a fixed path outside both directories.

The deployed name comes from the key rather than from the source,
so a file deployed as a dotfile is stored without the leading dot in the module directory.

When adding a deployed file:

1. Add the file to the directory of the module that should deploy it.
2. Deploy it from `<name>/<name>.nix` through `xdg.configFile`, `xdg.stateFile`, or `home.file`.
3. Update `scripts/apply.sh` and the template if the file must also be connected to user-managed files,
   as [Connecting to User-Managed Files](#connecting-to-user-managed-files) describes.
4. Add or extend tests under `tests/`, and update `tests/run.sh` if you add a new test script.

## Changing a Module's Packages or Settings

A module adds packages through `home.packages` and may set Home Manager options directly.

Typical examples are:

- a new tool in an existing toolchain or tool group
- a change to tool settings that are configured directly through Home Manager
- a change to how an existing file is deployed, which uses the options above

Every system that `flake.nix` declares has to keep evaluating,
so a package that is meaningful on only some of them needs a guard on the platform,
as `cpp/cpp.nix` does with `pkgs.stdenv.hostPlatform.isx86_64` for the multilib GCC.
An unguarded package that fails to evaluate on one of them breaks every output of that system.

A module may also set Home Manager options directly, as `platform/platform.nix` does for `targets.genericLinux`.
Use `lib.mkDefault` for an option a personal config repository should be able to override,
and a plain definition for one that has to hold for everyone, as `programs.home-manager.enable` does in `nix/nix.nix`.
Two plain definitions of an option carry equal priority; a boolean then conflicts instead of one overriding the other.
A mergeable option such as `nixpkgs.config` combines them instead, so a personal definition can still merge into it.
What a `lib.mkDefault` should default to follows the same rule as an option default, which [Adding a Module](#adding-a-module) describes.

When changing a module's packages or settings:

1. Update `<name>/<name>.nix`.
2. Add or extend tests under `tests/`, and update `tests/run.sh` if you add a new test script.

## Adding a Module

A module is a directory under `home-modules/` holding `<name>/<name>.nix` together with the configuration files it deploys:

```nix
{ pkgs, ... }:

{
  home.packages = [ pkgs.foo ];

  xdg.configFile."issl/foo/config.toml".source = ./config.toml;
}
```

If there is already a related module, update that one rather than adding another.

`default.nix` imports every module directory, so a new module needs no registration.
It reports the offending path when a directory holds no `<name>.nix`,
or when a `.nix` file sits directly under `home-modules/`, where nothing would load it.

If a module should only take effect in specific situations, declare an option for it and gate its `config` with `lib.mkIf`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.issl.foo.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    example = false;
    description = "Whether to enable the shared foo configuration.";
  };

  config = lib.mkIf config.issl.foo.enable {
    home.packages = [ pkgs.foo ];
  };
}
```

`zsh/zsh.nix` is one such module.
Its `lib.mkMerge` and the forced link inside it are specific to the login shell, not part of this pattern.

An option that changes what the environment installs is covered on both sides:
`flake.nix` declares a Home Manager configuration and a check for each state,
and the matrix of `.github/workflows/test.yaml` runs the tests for each.
Introducing one therefore reaches beyond the module.

Choose a default that asks nothing of the user:
`targets.genericLinux.gpu.enable` is off because enabling it asks every machine for a privileged one-time setup.
Within that constraint, follow what most users want:
`issl.zsh.enable` is on because most users here use Zsh, and turning it off costs a single option.

When adding a module:

1. Create `home-modules/<name>/<name>.nix`.
2. Add the files it deploys to the same directory, as [Adding a Deployed File](#adding-a-deployed-file) describes.
3. Update `scripts/apply.sh` and the template if the module must be connected to user-managed files,
   as [Connecting to User-Managed Files](#connecting-to-user-managed-files) describes.
4. Add `tests/test-<name>.sh`, and register it in `tests/run.sh`.

## Connecting to User-Managed Files

Since the shared environment does not own the files the user edits, what it deploys has to be imported or sourced from them.
Prefer declarative integration inside `home-modules/` first,
and connect the shared configuration to user-managed files only when that is not enough.

Both setup paths need that wiring, and they carry the same set of shared paths:

- the script-based setup does it imperatively in `scripts/apply.sh`
- the setup with a personal config repository does it declaratively in the user modules of the [template](11-setup-with-a-personal-config-repository.md)

Keep the two in step whenever a shared path is added, renamed, or removed.
The template is a separate repository, so that half of the change is a separate pull request.

Update `scripts/apply.sh` when the setup must connect the shared configuration
to user-managed files in a careful, incremental way that preserves existing user content.
In practice, this usually means adding include blocks or source commands to user-managed files such as:

- `~/.bash_profile`
- `~/.zshenv`
- `~/.cargo/config.toml`
- `~/.config/nix/nix.conf`

`prepend_block_once` puts the block at the top of the file and keeps the rest.
`~/.profile` and `~/.bashrc` are the exception:
`replace_with_block_once` reduces them to the block alone on the first run and keeps the previous file at `<file>.backup`.
Ubuntu seeds those two from `/etc/skel`, and that boilerplate runs after a prepended block and overrides the shared settings.
Both helpers do nothing once their begin marker is present, so later runs never touch the file again.

## Validating Changes

Validate a change in three steps: first run the pre-commit hooks, then confirm that it evaluates and builds,
and finally inspect what it actually produces.

Nix reads this repository through Git, so stage a new file before you validate:

```sh
git add -N <new files>
```

This records an intent to add and creates no commit.
Without it, Nix does not see the new files.
An untracked module directory is skipped without a word,
an untracked file that a module deploys fails the evaluation on a missing path, and a new test is silently left out.
A directory whose `<name>.nix` alone is untracked is reported as missing that file, however plainly it sits on disk.

1. Run the pre-commit hooks:

   ```sh
   prek run --files <changed files>
   ```

   This applies the formatters and the linters to the changed files.
   For Nix files, nixfmt formats the changed files, while deadnix and statix check the whole repository.
   See [Contribution Guidelines](93-contribution-guidelines.md) for how to install the hooks.

2. Run the checks:

   ```sh
   nix flake check --all-systems --show-trace
   ```

   This builds the checks of the system of this machine and catches Nix evaluation errors and build failures.
   They include the activation packages for the default and the Bash-only configuration,
   and the assertion that the GPU option stays off.
   `--all-systems` widens the evaluation to every system declared in `flake.nix` without building more,
   so a change that fails to evaluate on `aarch64-linux` is caught here rather than in CI.

3. Build the activation packages to inspect the result:

   ```sh
   nix build --out-link result-home .#checks.x86_64-linux.home
   nix build --out-link result-home-bash-only .#checks.x86_64-linux.home-bash-only
   ```

   Replace `x86_64-linux` with `aarch64-linux` to inspect the result for that architecture.

   Each build result contains what users receive:

   - `result-home/home-path/bin` holds the binaries the configuration installs.
   - `result-home/home-files` holds the files deployed through `xdg.configFile`, `xdg.stateFile`, and `home.file`,
     so a deployed file can be compared against its source in the module directory with `cmp`.
   - `result-home/activate` is the activation script that Home Manager runs on `switch`.

   The checks use the fixed username `issl` and home directory `/tmp/issl-home`,
   so paths under the build result refer to that home directory rather than yours.

## Documentation Updates

After updating or adding a module:

1. Update developer docs under `docs/` if the contributor workflow changes.
2. Update user docs under `docs/` if the user-visible setup behavior changes.
