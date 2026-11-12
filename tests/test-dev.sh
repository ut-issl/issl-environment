#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
nix_profile_bin="${home_dir}/.nix-profile/bin"

source "${common_dir}/tests/lib.sh"

test_commitizen_installation() {
  assert_command_path "${nix_profile_bin}/cz"
  cz version
}

test_prek_installation() {
  assert_command_path "${nix_profile_bin}/prek"
  prek --version
}

test_rumdl_installation() {
  assert_command_path "${nix_profile_bin}/rumdl"
  rumdl --version
}

test_tombi_installation() {
  assert_command_path "${nix_profile_bin}/tombi"
  tombi --version
}

test_typos_installation() {
  assert_command_path "${nix_profile_bin}/typos"
  typos --version
}

test_yamllint_installation() {
  assert_command_path "${nix_profile_bin}/yamllint"
  yamllint --version
}

main() {
  run_test test_commitizen_installation
  run_test test_prek_installation
  run_test test_rumdl_installation
  run_test test_tombi_installation
  run_test test_typos_installation
  run_test test_yamllint_installation
}

main "$@"
