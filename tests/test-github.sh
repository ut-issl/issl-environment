#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
nix_profile_bin="${home_dir}/.nix-profile/bin"

source "${common_dir}/tests/lib.sh"

test_gh_installation() {
  assert_command_path "${nix_profile_bin}/gh"
  gh --version
}

test_act_installation() {
  assert_command_path "${nix_profile_bin}/act"
  act --version
}

test_actionlint_installation() {
  assert_command_path "${nix_profile_bin}/actionlint"
  actionlint --version
}

test_zizmor_installation() {
  assert_command_path "${nix_profile_bin}/zizmor"
  zizmor --version
}

main() {
  run_test test_gh_installation
  run_test test_act_installation
  run_test test_actionlint_installation
  run_test test_zizmor_installation
}

main "$@"
