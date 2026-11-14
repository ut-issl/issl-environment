#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
config_dir="${CONFIG_DIR:?CONFIG_DIR is required}"
state_dir="${STATE_DIR:?STATE_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
nix_profile_bin="${home_dir}/.nix-profile/bin"
nix_profile_share="${home_dir}/.nix-profile/share"
default_zdotdir="${config_dir}/zsh"
login_shell_link="${state_dir}/issl/login-shell"
issl_enable_zsh="${ISSL_ENABLE_ZSH:?ISSL_ENABLE_ZSH is required}"

source "${common_dir}/tests/lib.sh"

test_shared_shell_files() {
  cmp "${common_dir}/home-modules/shell/env.sh" "${config_dir}/issl/shell/env.sh"
  cmp "${common_dir}/home-modules/shell/rc.sh" "${config_dir}/issl/shell/rc.sh"
  cmp "${common_dir}/home-modules/shell/dircolors" "${config_dir}/issl/shell/.dircolors"
  cmp "${common_dir}/home-modules/bash/bashrc.bash" "${config_dir}/issl/bash/.bashrc"
}

test_shell_env_can_be_sourced() {
  env -i \
    HOME="${home_dir}" \
    SHELL_ENV_PATH="${config_dir}/issl/shell/env.sh" \
    XDG_CONFIG_HOME="${config_dir}" \
    PATH='/usr/bin:/bin' \
    bash -e << 'EOF'
. "${SHELL_ENV_PATH}"
test "${ISSL_CONFIG_HOME}" = "${XDG_CONFIG_HOME}/issl"
test "${ISSL_PYTHON_HOME}" = "${XDG_CONFIG_HOME}/issl/python"
test "${ISSL_RUST_HOME}" = "${XDG_CONFIG_HOME}/issl/rust"
test "${CARGO_HOME}" = "${HOME}/.cargo"
test "${PYTHONSTARTUP}" = "${XDG_CONFIG_HOME}/python/pythonrc.py"
test "${PYTHON_HISTORY}" = "${XDG_STATE_HOME:-$HOME/.local/state}/python/python_history"
EOF
}

test_bash_startup_files() {
  assert_file "${home_dir}/.profile"
  assert_file "${home_dir}/.bash_profile"
  assert_file "${home_dir}/.bashrc"
}

test_profile_not_shadowed_by_bash_profile() {
  # Regression guard: ~/.bash_profile must source ~/.profile so it does not hide it.
  # shellcheck disable=SC2016  # $HOME is matched literally in the file content, not expanded.
  grep -Eq '(^|[[:space:]])(\.|source)[[:space:]]+"?(\$HOME|~)/\.profile"?' "${home_dir}/.bash_profile"
}

test_bash_startup_is_loaded() {
  # Drive a login + interactive bash and confirm the shared startup files ran (observed through their load guards)
  # and that env.sh put the Nix profile bin on PATH by itself, without the Nix installer's system-wide shell hooks.
  # shellcheck disable=SC2016  # ${...} inside the single-quoted -c argument expand in the subshell.
  env -i \
    HOME="${home_dir}" \
    XDG_CONFIG_HOME="${config_dir}" \
    PATH='/usr/bin:/bin' \
    TERM=dumb \
    bash -lic '
      ok=1
      [ "${ISSL_ENV_SH_LOADED:-0}" = "1" ] || { echo "login shell did not load the shared env.sh" >&2; ok=0; }
      [ "${ISSL_BASHRC_LOADED:-0}" = "1" ] || { echo "interactive shell did not load the shared bashrc" >&2; ok=0; }
      [ "$(command -v colordiff)" = "${HOME}/.nix-profile/bin/colordiff" ] || { echo "env.sh did not add the Nix profile bin to PATH" >&2; ok=0; }
      [ "$(command -v nix)" = "${HOME}/.nix-profile/bin/nix" ] || { echo "env.sh did not put the Nix profile bin before the default profile" >&2; ok=0; }
      [ "${ok}" = "1" ]
    '
}

test_shared_shell_tools() {
  assert_file "${nix_profile_share}/bash-completion/bash_completion"

  assert_command_path "${nix_profile_bin}/colordiff"
  colordiff --version

  assert_command_path "${nix_profile_bin}/dircolors"
  dircolors --version

  assert_command_path "${nix_profile_bin}/ls"
  ls --classify=auto -d . > /dev/null
}

test_shellcheck_installation() {
  assert_command_path "${nix_profile_bin}/shellcheck"
  shellcheck --version
}

test_shfmt_installation() {
  assert_command_path "${nix_profile_bin}/shfmt"
  shfmt --version
}

test_zsh_enabled() {
  assert_command_path "${nix_profile_bin}/zsh"
  zsh --version
}

test_shared_zsh_files() {
  cmp "${common_dir}/home-modules/zsh/zprofile.zsh" "${config_dir}/issl/zsh/.zprofile"
  cmp "${common_dir}/home-modules/zsh/zshrc.zsh" "${config_dir}/issl/zsh/.zshrc"
}

test_zsh_startup_files() {
  assert_file "${home_dir}/.zshenv"
  assert_file "${default_zdotdir}/.zprofile"
  assert_file "${default_zdotdir}/.zshrc"
}

test_zsh_startup_is_loaded() {
  # shellcheck disable=SC2016  # ${...} inside the single-quoted -c argument expand in the subshell.
  env -i \
    HOME="${home_dir}" \
    XDG_CONFIG_HOME="${config_dir}" \
    PATH='/usr/bin:/bin' \
    TERM=dumb \
    "${nix_profile_bin}/zsh" -lic '
      ok=1
      [ "${ISSL_ENV_SH_LOADED:-0}" = "1" ] || { echo "login shell did not load the shared env.sh" >&2; ok=0; }
      [ "${ISSL_ZSHRC_LOADED:-0}" = "1" ] || { echo "interactive shell did not load the shared zshrc" >&2; ok=0; }
      [ "$(command -v colordiff)" = "${HOME}/.nix-profile/bin/colordiff" ] || { echo "env.sh did not add the Nix profile bin to PATH" >&2; ok=0; }
      [ "${ok}" = "1" ]
    '
}

assert_login_shell_link_targets() {
  local expected="$1"
  local actual_target
  local expected_target

  assert_symlink "${login_shell_link}"
  actual_target="$(readlink -f "${login_shell_link}")"
  expected_target="$(readlink -f "${expected}")"
  assert_equal "${actual_target}" "${expected_target}"
}

assert_shell_variable_is_corrected() {
  local shell_bin="$1"
  local expected="$2"

  env -i \
    HOME="${home_dir}" \
    SHELL_ENV_PATH="${config_dir}/issl/shell/env.sh" \
    XDG_CONFIG_HOME="${config_dir}" \
    XDG_STATE_HOME="${state_dir}" \
    SHELL="${login_shell_link}" \
    EXPECTED_SHELL="${expected}" \
    PATH='/usr/bin:/bin' \
    "${shell_bin}" << 'EOF'
. "${SHELL_ENV_PATH}"
test "${SHELL}" = "${EXPECTED_SHELL}"
EOF
}

test_login_shell_is_managed_for_zsh() {
  assert_login_shell_link_targets "${nix_profile_bin}/zsh"
  assert_shell_variable_is_corrected bash "${home_dir}/.nix-profile/bin/zsh"
  assert_shell_variable_is_corrected "${nix_profile_bin}/zsh" "${home_dir}/.nix-profile/bin/zsh"
  assert_executable "${nix_profile_bin}/issl-login-shell-setup"
}

test_login_shell_is_managed_for_bash() {
  assert_login_shell_link_targets /bin/bash
  assert_shell_variable_is_corrected bash /bin/bash
  assert_not_exists "${nix_profile_bin}/issl-login-shell-setup"
}

test_zsh_disabled() {
  assert_not_exists "${nix_profile_bin}/zsh"
  assert_not_exists "${home_dir}/.zshenv"
  assert_not_exists "${default_zdotdir}/.zprofile"
  assert_not_exists "${default_zdotdir}/.zshrc"
}

main() {
  run_test test_shared_shell_files
  run_test test_shell_env_can_be_sourced
  run_test test_bash_startup_files
  run_test test_bash_startup_is_loaded
  run_test test_profile_not_shadowed_by_bash_profile
  run_test test_shared_shell_tools
  run_test test_shellcheck_installation
  run_test test_shfmt_installation

  if [[ ${issl_enable_zsh} == '1' ]]; then
    run_test test_zsh_enabled
    run_test test_shared_zsh_files
    run_test test_zsh_startup_files
    run_test test_zsh_startup_is_loaded
    run_test test_login_shell_is_managed_for_zsh
  else
    run_test test_zsh_disabled
    run_test test_login_shell_is_managed_for_bash
  fi
}

main "$@"
