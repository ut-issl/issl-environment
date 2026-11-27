#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
nix_profile_bin="${home_dir}/.nix-profile/bin"
nix_profile_share="${home_dir}/.nix-profile/share"

source "${common_dir}/tests/lib.sh"

test_utokyo_wifi_installation() {
  assert_command_path "${nix_profile_bin}/utokyo-wifi"
  utokyo-wifi --version
}

test_utokyo_wifi_completions() {
  assert_file "${nix_profile_share}/bash-completion/completions/utokyo-wifi.bash"
  assert_file "${nix_profile_share}/zsh/site-functions/_utokyo-wifi"
}

main() {
  run_test test_utokyo_wifi_installation
  run_test test_utokyo_wifi_completions
}

main "$@"
