#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
config_dir="${CONFIG_DIR:?CONFIG_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
nix_profile_bin="${home_dir}/.nix-profile/bin"
export RUSTUP_HOME="${home_dir}/.rustup"

source "${common_dir}/tests/lib.sh"

test_rustup_installation() {
  assert_command_path "${nix_profile_bin}/rustup"
  rustup --version
}

test_rustc_installation() {
  command -v rustc > /dev/null 2>&1
  rustc --version
}

test_cargo_installation() {
  command -v cargo > /dev/null 2>&1
  cargo --version
}

test_cargo_about_installation() {
  assert_command_path "${nix_profile_bin}/cargo-about"
  cargo about --version
}

test_cargo_deny_installation() {
  assert_command_path "${nix_profile_bin}/cargo-deny"
  cargo deny --version
}

test_cargo_hack_installation() {
  assert_command_path "${nix_profile_bin}/cargo-hack"
  cargo hack --version
}

test_cargo_llvm_cov_installation() {
  assert_command_path "${nix_profile_bin}/cargo-llvm-cov"
  cargo llvm-cov --version
}

test_cargo_nextest_installation() {
  assert_command_path "${nix_profile_bin}/cargo-nextest"
  cargo nextest --version
}

test_dist_installation() {
  assert_command_path "${nix_profile_bin}/dist"
  dist --version
}

test_default_toolchain_stable() {
  rustup show active-toolchain | grep -Eq '^stable(-|$)'
}

test_shared_rust_config_file() {
  cmp "${common_dir}/home-modules/rust/config.toml" "${config_dir}/issl/rust/config.toml"
}

test_cargo_config_include() {
  local cargo_config_path="${home_dir}/.cargo/config.toml"

  assert_file "${cargo_config_path}"
  grep -Fq "${config_dir}/issl/rust/config.toml" "${cargo_config_path}"
}

main() {
  run_test test_rustup_installation
  run_test test_rustc_installation
  run_test test_cargo_installation
  run_test test_cargo_about_installation
  run_test test_cargo_deny_installation
  run_test test_cargo_hack_installation
  run_test test_cargo_llvm_cov_installation
  run_test test_cargo_nextest_installation
  run_test test_dist_installation
  run_test test_default_toolchain_stable
  run_test test_shared_rust_config_file
  run_test test_cargo_config_include
}

main "$@"
