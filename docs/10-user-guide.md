# User Guide

## Supported Platforms

- Ubuntu 22.04, 24.04 and 26.04 are supported and tested in CI on x86_64.
  Ubuntu on WSL is supported as well.
- Other Linux distributions are supported on a best-effort basis and are not tested.
  The Home Manager configuration does not depend on the distribution,
  but the optional Docker Engine setup during host bootstrapping
  supports only Ubuntu, its derivatives, and Debian stable releases,
  and on other distributions it is skipped with a warning instead of being offered or installed.
- macOS and NixOS are not supported.

## How to Use

This repository can be used in two ways:

1. Create and maintain a personal Nix configuration repository with Home Manager
   that is designed to import this ISSL config from the start.
   - Recommended for individual users who want customization with reproducibility and long-term maintainability.
   - See [setup with a personal config repository](11-setup-with-a-personal-config-repository.md).

2. Use the setup script provided by this repository.
   - Recommended for shared PCs or users who do not need reproducible personal customization.
   - See [script-based setup](12-script-based-setup.md).
