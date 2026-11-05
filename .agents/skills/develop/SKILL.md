---
name: develop
description: >-
  Guide development of the shared ISSL environment:
  adding or updating tools, modules, the files they deploy, and tests.
  Use when asked to add a tool or package to the shared environment,
  update an existing module or a file it deploys, or modify how the environment is configured.
  Do not use for documentation-only changes, CI/CD pipeline changes,
  or dependency version bumps handled by Renovate.
---

# Develop the Shared Environment

Help update or extend the shared ISSL environment, one change at a time:
add a tool, update a module, change a file it deploys, or adjust the imperative setup.

`docs/92-updating-or-adding-a-module.md` holds the conventions of this repository.
Read it and follow it rather than working from a summary; this skill covers only how to carry the work out.
Every `§` below names a section of that page.
`docs/93-contribution-guidelines.md` holds the commit and pull request conventions.

Converse in the language the user writes in, but keep all edits (code, comments, commit messages, etc.) in English.
Leave all changes uncommitted; committing and pushing are up to the user unless explicitly requested.
Never write secrets (tokens, private keys, credentials) into the repository;
what this repository deploys reaches every lab machine.
Never run `scripts/apply.sh`, `scripts/setup.sh`, or `home-manager switch`
against the user's real home environment without explicit approval;
use prek and `nix flake check --all-systems` for local validation instead.

Before starting, verify that `nix` is available (`command -v nix`).
Nix is required for developing this repository;
changes cannot be validated without it, and bugs here affect the entire lab.
If Nix is not available, stop and ask the user to set it up first.

## 1. Understand the request

Identify what the user wants: a new tool in the shared environment,
a change to an existing tool's configuration, a new deployed file, or a structural change.
Ask only if the request is ambiguous.

## 2. Check what already exists

Before adding anything, scan the actual repository state (not the docs, which may lag):

- `home-modules/` for a module that already covers the tool or area.
  Each directory there is one module, together with the configuration files it deploys.
- `home-modules/zsh/zsh.nix` for a conditional module, read alongside § "Adding a Module".
- `tests/` for existing test coverage.
- `scripts/apply.sh` for existing imperative wiring.

If there is already a related module, update it rather than creating a new one.

## 3. Research the package and its options

For a new tool:

- Settle first whether the package is a graphical application, and stop there if it is:
  say that it does not belong in the shared environment, and do not go on to the license check or to a placement.
  § "What Belongs in the Shared Environment" has the reasons.
  Point the user to `docs/13-package-management-practices.md` rather than to a particular alternative:
  whether such an application can live in a personal config repository
  or has to stay with the distribution depends on the host integration it needs.
- Look the package up in Nixpkgs at the pinned revision:
  read the `nixpkgs` entry's `locked.rev` from `flake.lock` and run `nix search github:NixOS/nixpkgs/<rev> <name>`.
  Read the `nixpkgs-unstable` entry instead for a package
  that § "Changing a Module's Packages or Settings" lets come from it.
- Work out whether the package is meaningful on every system that `flake.nix` declares,
  and guard it on the platform if it is not, as § "Changing a Module's Packages or Settings" describes.
- An unfree package needs an explicit yes from the user before you add it,
  on top of the justification that § "What Belongs in the Shared Environment" asks for in the pull request.
- If the package is not in Nixpkgs, report honestly and let the user decide.
  Never add flake inputs or overlays without an explicit yes.

## 4. Decide where the change goes

The page has one section per kind of change.
Work out which one the request is, and follow that section rather than improvising:

- only the contents of a file this repository already deploys → § "Changing a Deployed File"
- a configuration file this repository does not deploy yet → § "Adding a Deployed File"
- a package or a Home Manager option in an existing module → § "Changing a Module's Packages or Settings"
- a distinct area with no module of its own → § "Adding a Module"

Reuse the existing `issl.zsh.enable` option where it fits.
A new one reaches `flake.nix` and the CI matrix as § "Adding a Module" describes,
so confirm with the user before going that route.

If more than one placement is reasonable, present the options briefly with a recommendation
and let the user choose before editing.

## 5. Implement the change

Match the style of the existing modules.
Formatting is enforced by nixfmt via the pre-commit hooks.

Where § "Connecting to User-Managed Files" calls for a change to `scripts/apply.sh`,
follow the existing marker pattern (`# >>> ISSL <name> >>>` / `# <<< ISSL <name> <<<`).
That section also names the template repository as the other half of the same wiring,
so say in the wrap-up whether a change there is needed.

## 6. Add or update tests

Every module should have corresponding test coverage under `tests/`.

Tests run in CI against a freshly applied environment (the `script-based` job of `.github/workflows/test.yaml` and the reusable
`.github/workflows/test-config-repository.yaml` both set `HOME_DIR`/`CONFIG_DIR`/`STATE_DIR` and run `tests/run.sh`).
Do not try to run them locally unless this machine has the shared environment applied;
local validation is prek plus the Nix validation in step 7,
which can confirm installed binaries and deployed files without applying anything.

If a test file for this area already exists (e.g. `tests/test-<tool>.sh`), extend it.
If not, create a new `tests/test-<tool>.sh` following the existing pattern:

1. Copy the header from the closest existing test: `set -Eeuo pipefail`, the required environment variable guards
   (`HOME_DIR:?` always; `CONFIG_DIR:?` when inspecting deployed config or user-managed file wiring;
   `STATE_DIR:?` when inspecting what a module deploys under `~/.local/state/issl/`), the `COMMON_DIR` fallback, and `nix_profile_bin="${home_dir}/.nix-profile/bin"`.
   Then source `tests/lib.sh` for the `run_test` helper
   and the failure-reporting ERR trap (which needs the `-E` in `set -Eeuo pipefail`).
2. Define test functions (e.g. `test_<tool>_installation`, `test_<tool>_config`).
3. Call them via `run_test` in a `main` function.
4. Make the script executable.
5. Register the new test script in `tests/run.sh` by adding its name to the loop list.

For a module that takes effect only in specific configurations (like `zsh/zsh.nix`),
gate its assertions on the corresponding environment variable
inside the relevant test script (see `ISSL_ENABLE_ZSH` in `test-shell.sh`) instead of adding a separate unconditional script.

Common assertion patterns (helpers are defined in `tests/lib.sh`):

- **Tool installation**: call `assert_command_path "${nix_profile_bin}/<binary>"`,
  then run the tool once (e.g. `<binary> --version`).
- **Values and paths**: use `assert_equal`, `assert_file`, `assert_symlink`, `assert_executable`, and `assert_not_exists`
  instead of bare `[[ ]]` so a failure prints what was expected and what was found.
- **File deployment**: use `cmp` to verify the deployed file matches the source in the module's directory.
- **Config wiring**: use `grep -Fq` to check that include or source lines are present in user-managed files.

Keep each helper call on a single line, because a failure report shows only the source line of the call.

## 7. Validate

Run validation in this order:

1. Run `prek run --files <changed files> --skip no-commit-to-branch` and fix what it reports.
   If `prek` is not on PATH, use `uvx prek` instead.
2. Run the Nix validation of § "Validating Changes": stage the new files, run the flake checks,
   then build the activation packages and inspect the installed binaries and deployed files.
   Build for the system of this machine, not the one in the example command.
   Remove the `result-*` symlinks when done.

## 8. Wrap up

Summarize what was changed, what was validated, and what was skipped.

If the change affects contributor workflow or user-visible setup behavior,
update the relevant documentation under `docs/` as part of this task (see § "Documentation Updates").

If the user later asks for a commit or PR, follow the Conventional Commits format described in `docs/93-contribution-guidelines.md`,
and suggest an appropriate version bump label (`update::major`, `update::minor`, or `update::patch`) for the pull request.
Leave all changes uncommitted until then.
