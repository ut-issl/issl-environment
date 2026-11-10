#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
config_dir="${CONFIG_DIR:?CONFIG_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
nix_profile_bin="${home_dir}/.nix-profile/bin"
pythonrc_path="${config_dir}/python/pythonrc.py"
issl_python_home="${config_dir}/issl/python"
issl_pythonrc_path="${issl_python_home}/pythonrc.py"

source "${common_dir}/tests/lib.sh"

_is_python_ge_3_13() {
  local py_version major minor
  py_version="$(uv run --no-project --python=3 python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  IFS=. read -r major minor <<< "${py_version}"
  [[ ${major} -gt 3 || (${major} -eq 3 && ${minor} -ge 13) ]]
}

_is_libedit() {
  local result
  result="$(uv run --no-project --python=3 python -c '
import sys
try:
    import readline
except ImportError:
    print("no"); raise SystemExit
if sys.version_info >= (3, 13):
    print("yes" if getattr(readline, "backend", "") == "editline" else "no")
else:
    print("yes" if "libedit" in getattr(readline, "__doc__", "") else "no")
')"
  [[ ${result} == 'yes' ]]
}

_python_exe() {
  uv run --no-project --python=3 python -c 'import sys; print(sys.executable)'
}

test_uv_installation() {
  assert_command_path "${nix_profile_bin}/uv"
  uv --version
}

test_shared_pythonrc_file() {
  cmp "${common_dir}/home-modules/python/pythonrc.py" "${issl_pythonrc_path}"
}

test_user_python_startup_file() {
  assert_file "${pythonrc_path}"
  grep -Fq 'runpy.run_path(str(shared_pythonrc), run_name="__main__")' "${pythonrc_path}"
}

test_python_startup_is_loaded() {
  local marker_dir
  marker_dir="$(mktemp -d)"

  echo 'import sys; sys.exit(0 if sys.displayhook is not sys.__displayhook__ else 1)' \
    | ISSL_PYTHON_HOME="${issl_python_home}" \
      PYTHONSTARTUP="${pythonrc_path}" \
      PYTHON_HISTORY="${marker_dir}/history" \
      TERM=dumb \
      uv run --no-project --python=3 python -i

  if _is_libedit; then
    assert_file "${marker_dir}/history.editline"
    assert_not_exists "${marker_dir}/history"
  else
    assert_file "${marker_dir}/history"
    assert_not_exists "${marker_dir}/history.editline"
  fi
}

test_python_startup_pyrepl_history() {
  if ! _is_python_ge_3_13; then
    echo 'Skipping: Python < 3.13 (no pyrepl)'
    return 0
  fi

  local hist_base python_exe
  hist_base="$(mktemp -d)/state/python"
  python_exe="$(_python_exe)"

  ISSL_PYTHON_HOME="${issl_python_home}" \
    PYTHONSTARTUP="${pythonrc_path}" \
    PYTHON_HISTORY="${hist_base}/history" \
    TERM=xterm \
    uv run --no-project --python=3 python "${common_dir}/tests/pty-driver.py" "${python_exe}"

  assert_file "${hist_base}/history"
  grep -q 'exit()' "${hist_base}/history"

  if _is_libedit; then
    assert_not_exists "${hist_base}/history.editline"
  fi
}

test_python_startup_basic_repl_libedit_history() {
  if ! _is_python_ge_3_13; then
    echo 'Skipping: Python < 3.13 (no basic REPL redirect needed)'
    return 0
  fi
  if ! _is_libedit; then
    echo 'Skipping: readline backend is not libedit'
    return 0
  fi

  local hist_base python_exe
  hist_base="$(mktemp -d)/state/python"
  python_exe="$(_python_exe)"

  ISSL_PYTHON_HOME="${issl_python_home}" \
    PYTHONSTARTUP="${pythonrc_path}" \
    PYTHON_HISTORY="${hist_base}/history" \
    PYTHON_BASIC_REPL=1 \
    TERM=xterm \
    uv run --no-project --python=3 python "${common_dir}/tests/pty-driver.py" "${python_exe}"

  assert_file "${hist_base}/history.editline"
  grep -q 'exit()' "${hist_base}/history.editline"
  assert_not_exists "${hist_base}/history"
}

main() {
  run_test test_uv_installation
  run_test test_shared_pythonrc_file
  run_test test_user_python_startup_file
  run_test test_python_startup_is_loaded
  run_test test_python_startup_pyrepl_history
  run_test test_python_startup_basic_repl_libedit_history
}

main "$@"
