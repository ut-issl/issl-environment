# Coding Agents

This environment installs Codex and passes the [package management practices](13-package-management-practices.md) on to coding agents,
so that an agent installs software the way the practices describe.

## Codex

Codex reads the practices as the `issl-environment` skill from `~/.agents/skills/`.

In addition, `~/.codex/rules/issl-environment.rules`, under `$CODEX_HOME` instead when Home Manager sets it,
blocks the global install commands that the practices rule out,
such as `pip install`, `uv tool install`, `npm install -g`, and `cargo install`.

- The rules match a command by its leading words,
  so they catch the usual spellings but not every one, such as a flag placed after the package name.
- The rules apply only to the commands that Codex runs, so a command you enter yourself still runs.
- The file is a copy rather than a link, and every switch overwrites it,
  so keep your own Codex rules in another file.
- Home Manager does not track the copy, so delete it by hand if you stop using the shared environment.

## Claude Code

This environment does not install Claude Code, so enable it in your personal config repository.
Once installed, it reads the practices as a rule from `~/.claude/rules/issl-environment.md`.
