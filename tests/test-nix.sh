#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
config_dir="${CONFIG_DIR:?CONFIG_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
nix_profile_bin="${home_dir}/.nix-profile/bin"
nix_config_path="${config_dir}/nix/nix.conf"
issl_nix_config_path="${config_dir}/issl/nix/nix.conf"

source "${common_dir}/tests/lib.sh"

test_nix_installation() {
  command -v nix > /dev/null
  nix --version
}

test_shared_nix_config() {
  cmp "${common_dir}/home-modules/nix/nix.conf" "${issl_nix_config_path}"
}

test_nix_conf_include() {
  assert_file "${nix_config_path}"
  grep -Fq "!include ${issl_nix_config_path}" "${nix_config_path}"
}

test_nix_command_available_without_extra_flags() {
  env \
    HOME="${home_dir}" \
    XDG_CONFIG_HOME="${config_dir}" \
    nix profile list > /dev/null
}

test_home_manager_installation() {
  assert_command_path "${nix_profile_bin}/home-manager"
  home-manager --version
}

test_nixfmt_installation() {
  assert_command_path "${nix_profile_bin}/nixfmt"
  nixfmt --version
}

test_statix_installation() {
  assert_command_path "${nix_profile_bin}/statix"
  statix --help
}

test_deadnix_installation() {
  assert_command_path "${nix_profile_bin}/deadnix"
  deadnix --version
}

test_nix_search_cli_installation() {
  assert_command_path "${nix_profile_bin}/nix-search"
  nix-search --help > /dev/null
}

test_nix_memory_limit_wrapper_without_user_session() {
  local limited

  assert_file "${nix_profile_bin}/nix"
  limited="$(
    env -u XDG_RUNTIME_DIR \
      HOME="${home_dir}" \
      XDG_CONFIG_HOME="${config_dir}" \
      "${nix_profile_bin}/nix" eval --impure --raw --expr 'builtins.getEnv "ISSL_NIX_MEMORY_LIMITED"'
  )"
  assert_equal "${limited}" ""
}

test_nix_memory_limit_wrapper_with_user_session() {
  local fake_dir
  local calls
  local limited
  local limited_after_option
  local busy_call
  local idle_call
  local unreadable
  local old_systemd_calls

  fake_dir="$(mktemp -d)"
  cat > "${fake_dir}/systemctl" << 'SCRIPT'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${FAKE_CALLS}"
if [[ -n ${FAKE_SHOW_FAILS:-} && $2 == show ]]; then
  exit 1
elif [[ $1 == --user && $2 == show && $* == *--value* ]]; then
  echo 1
elif [[ $1 == --user && $2 == show ]]; then
  printf 'TasksCurrent=%s\nMemoryCurrent=%s\n' \
    "${FAKE_TASKS_CURRENT:-[not set]}" "${FAKE_MEMORY_CURRENT:-[not set]}"
fi
SCRIPT
  cat > "${fake_dir}/systemd-run" << 'SCRIPT'
#!/usr/bin/env bash
if [[ $1 == --version ]]; then
  echo "systemd ${FAKE_SYSTEMD_VERSION:-255} (fake)"
  exit 0
fi
printf 'systemd-run %s\n' "$*" >> "${FAKE_CALLS}"
while [[ $# -gt 0 && $1 != -- ]]; do
  shift
done
shift
exec "$@"
SCRIPT
  chmod +x "${fake_dir}/systemctl" "${fake_dir}/systemd-run"
  uv run --no-project --python=3 python -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
    "${fake_dir}/bus"

  limited="$(
    env \
      HOME="${home_dir}" \
      XDG_CONFIG_HOME="${config_dir}" \
      XDG_RUNTIME_DIR="${fake_dir}" \
      FAKE_CALLS="${fake_dir}/calls" \
      PATH="${fake_dir}:${PATH}" \
      "${nix_profile_bin}/nix" eval --impure --raw --expr 'builtins.getEnv "ISSL_NIX_MEMORY_LIMITED"'
  )"
  limited_after_option="$(
    env \
      HOME="${home_dir}" \
      XDG_CONFIG_HOME="${config_dir}" \
      XDG_RUNTIME_DIR="${fake_dir}" \
      FAKE_CALLS="${fake_dir}/calls" \
      PATH="${fake_dir}:${PATH}" \
      "${nix_profile_bin}/nix" --option flake-registry run eval --impure --raw \
      --expr 'builtins.getEnv "ISSL_NIX_MEMORY_LIMITED"'
  )"
  env \
    HOME="${home_dir}" \
    XDG_CONFIG_HOME="${config_dir}" \
    XDG_RUNTIME_DIR="${fake_dir}" \
    FAKE_CALLS="${fake_dir}/busy-calls" \
    FAKE_TASKS_CURRENT=1 \
    FAKE_MEMORY_CURRENT=1099511627776 \
    PATH="${fake_dir}:${PATH}" \
    "${nix_profile_bin}/nix" eval --expr 1 > /dev/null
  env \
    HOME="${home_dir}" \
    XDG_CONFIG_HOME="${config_dir}" \
    XDG_RUNTIME_DIR="${fake_dir}" \
    FAKE_CALLS="${fake_dir}/idle-calls" \
    FAKE_TASKS_CURRENT=0 \
    FAKE_MEMORY_CURRENT=1099511627776 \
    PATH="${fake_dir}:${PATH}" \
    "${nix_profile_bin}/nix" eval --expr 1 > /dev/null
  unreadable="$(
    env \
      HOME="${home_dir}" \
      XDG_CONFIG_HOME="${config_dir}" \
      XDG_RUNTIME_DIR="${fake_dir}" \
      FAKE_CALLS="${fake_dir}/unreadable-calls" \
      FAKE_SHOW_FAILS=1 \
      PATH="${fake_dir}:${PATH}" \
      "${nix_profile_bin}/nix" eval --impure --raw --expr 'builtins.getEnv "ISSL_NIX_MEMORY_LIMITED"'
  )"
  env \
    HOME="${home_dir}" \
    XDG_CONFIG_HOME="${config_dir}" \
    XDG_RUNTIME_DIR="${fake_dir}" \
    FAKE_CALLS="${fake_dir}/old-systemd-calls" \
    FAKE_SYSTEMD_VERSION=249 \
    PATH="${fake_dir}:${PATH}" \
    "${nix_profile_bin}/nix" eval --expr 1 > /dev/null
  old_systemd_calls="$(< "${fake_dir}/old-systemd-calls")"
  calls="$(< "${fake_dir}/calls")"
  busy_call="$(grep 'set-property' "${fake_dir}/busy-calls")"
  idle_call="$(grep 'set-property' "${fake_dir}/idle-calls")"
  rm -rf "${fake_dir}"

  assert_equal "${limited}" 1
  assert_equal "${limited_after_option}" 1
  grep -Eq '^systemctl --user set-property --runtime issl-nix\.slice MemoryMax=[0-9]+K MemorySwapMax=0$' <<< "${calls}"
  grep -Eq '^systemd-run --user --scope --quiet --collect --slice=issl-nix\.slice --expand-environment=no -- ' <<< "${calls}"
  grep -Eq '^systemd-run --user --scope --quiet --collect --slice=issl-nix\.slice -- ' <<< "${old_systemd_calls}"
  assert_equal "${busy_call}" 'systemctl --user set-property --runtime issl-nix.slice MemoryMax=1181116006K MemorySwapMax=0'
  [[ ${idle_call} != *MemoryMax=1181116006K* ]]
  assert_equal "${unreadable}" ""
}

test_nix_memory_limit_wrapper_with_real_user_session() {
  local runtime_dir
  local probe_error
  local systemd_version
  local limited
  local slice_info

  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [[ ! -d ${runtime_dir} ]]; then
    echo "Skipping: no systemd user session (${runtime_dir} is missing)"
    return 0
  fi
  if [[ ! -S "${runtime_dir}/bus" ]]; then
    echo "Skipping: no systemd user session (${runtime_dir}/bus is missing)"
    return 0
  fi
  if ! XDG_RUNTIME_DIR="${runtime_dir}" systemctl --user show-environment > /dev/null 2>&1; then
    echo "Skipping: no systemd user session (systemctl --user is unreachable through ${runtime_dir})"
    return 0
  fi
  if ! probe_error="$(XDG_RUNTIME_DIR="${runtime_dir}" systemd-run --user --scope --quiet --collect -- true 2>&1 > /dev/null)"; then
    echo "Skipping: the systemd user session cannot start a scope for this process (${probe_error})"
    return 0
  fi

  systemd_version="$(systemd-run --version)"
  echo "${systemd_version%%$'\n'*}"
  limited="$(
    env \
      -u ISSL_NIX_MEMORY_LIMITED \
      HOME="${home_dir}" \
      XDG_CONFIG_HOME="${config_dir}" \
      XDG_RUNTIME_DIR="${runtime_dir}" \
      "${nix_profile_bin}/nix" eval --impure --raw --expr 'builtins.getEnv "ISSL_NIX_MEMORY_LIMITED"'
  )"
  slice_info="$(
    XDG_RUNTIME_DIR="${runtime_dir}" systemctl --user show --property=ControlGroup --property=MemoryMax issl-nix.slice
  )"
  echo "${slice_info}"

  assert_equal "${limited}" 1
  [[ ${slice_info} =~ (^|$'\n')MemoryMax=[0-9]+($'\n'|$) ]]
}

main() {
  run_test test_nix_installation
  run_test test_shared_nix_config
  run_test test_nix_conf_include
  run_test test_nix_command_available_without_extra_flags
  run_test test_home_manager_installation
  run_test test_nixfmt_installation
  run_test test_statix_installation
  run_test test_deadnix_installation
  run_test test_nix_search_cli_installation
  run_test test_nix_memory_limit_wrapper_without_user_session
  run_test test_nix_memory_limit_wrapper_with_user_session
  run_test test_nix_memory_limit_wrapper_with_real_user_session
}

main "$@"
