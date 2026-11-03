# issl-environment

[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04%20%7C%2026.04-E95420.svg?style=flat&logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![Built with Nix](https://img.shields.io/badge/Built_with_Nix-41439a.svg?style=flat&logo=nixos&logoColor=white)](https://nixos.org)
[![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg?style=flat)](#license)
[![prek](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/j178/prek/master/docs/assets/badge-v0.json)](https://github.com/j178/prek)
[![CI](https://github.com/ut-issl/issl-environment/actions/workflows/ci.yaml/badge.svg)](https://github.com/ut-issl/issl-environment/actions/workflows/ci.yaml)
[![Test](https://github.com/ut-issl/issl-environment/actions/workflows/test.yaml/badge.svg)](https://github.com/ut-issl/issl-environment/actions/workflows/test.yaml)

A repository for distributing a reproducible and maintainable shared environment for ISSL.

> [!WARNING]
> This repository is an early-stage prototype and is under active development.
> It may be made private or deleted without prior notice.
> It is provided as-is, without user support or compatibility guarantees.
> Use it at your own risk.

## Supported Platforms

Ubuntu 22.04, 24.04 and 26.04 are supported and tested in CI, and Ubuntu on WSL is supported as well.
Other Linux distributions are supported on a best-effort basis.
See [Supported Platforms](docs/10-user-guide.md#supported-platforms) for details.

## How to Use

This repository can be used in two ways:

1. Create and maintain a personal Nix configuration repository with Home Manager
   that is designed to import this ISSL config from the start.
   - See [setup with a personal config repository](docs/11-setup-with-a-personal-config-repository.md).

2. Use the setup script provided by this repository.
   - See [script-based setup](docs/12-script-based-setup.md).

For more details, see the [User Guide](docs/10-user-guide.md).

## For Developers

See [Developer Guide](docs/90-developer-guide.md).

This repository ships a skill for coding agents that assists development; see [agent skill](docs/92-updating-or-adding-a-module.md#agent-skill).

## License

Licensed under either of [MIT license](LICENSE-MIT) or [Apache License, Version 2.0](LICENSE-APACHE) at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this software
by you, as defined in the Apache-2.0 license, shall be dually licensed as above, without any additional terms or conditions.
