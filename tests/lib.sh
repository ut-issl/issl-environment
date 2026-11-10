# shellcheck shell=bash
# Shared helpers for the ISSL environment tests.
#
# Sourcing scripts must enable errtrace (set -E) so the ERR trap below also
# fires for failures inside functions.

# Report the location and command of the first failing assertion.
# shellcheck disable=SC2317  # invoked via the ERR trap, not directly.
_issl_test_failed() {
  local status="$?"
  local command="${BASH_COMMAND}"
  local source_line

  # Report only from the top-level shell, not from subshells or command substitutions.
  if [[ ${BASH_SUBSHELL} -eq 0 ]]; then
    # Show the calling source line when the failure came from a return of a function.
    if [[ ${command} == return || ${command} == 'return '* ]]; then
      source_line="$(sed -n "${BASH_LINENO[0]}s/^[[:space:]]*//p" "${BASH_SOURCE[1]}" 2> /dev/null)" \
        && [[ -n ${source_line} ]] \
        && command="${source_line}"
    fi
    printf 'FAILED: %s:%s: %s (exit %s)\n' \
      "${BASH_SOURCE[1]##*/}" "${BASH_LINENO[0]}" "${command}" "${status}" >&2
  fi
}
trap _issl_test_failed ERR
shopt -s inherit_errexit

# Run a named test, logging it so progress is visible in the test output.
run_test() {
  printf -- '-- %s\n' "$1"
  "$@"
}

# Assertion helpers. On failure, each prints the details and returns 1 so the
# ERR trap reports the line of the calling test.

assert_equal() {
  local actual="$1"
  local expected="$2"

  [[ ${actual} == "${expected}" ]] || {
    printf '  expected: %s\n  actual:   %s\n' "${expected}" "${actual}" >&2
    return 1
  }
}

assert_file() {
  [[ -f $1 ]] || {
    printf '  not a regular file: %s\n' "$1" >&2
    return 1
  }
}

assert_symlink() {
  [[ -L $1 ]] || {
    printf '  not a symlink: %s\n' "$1" >&2
    return 1
  }
}

assert_executable() {
  [[ -x $1 ]] || {
    printf '  not executable: %s\n' "$1" >&2
    return 1
  }
}

assert_not_exists() {
  [[ ! -e $1 && ! -L $1 ]] || {
    printf '  unexpectedly exists: %s\n' "$1" >&2
    return 1
  }
}

# Assert that the executable at a path is the command of the same name found on PATH.
assert_command_path() {
  local path="$1"

  assert_executable "${path}" || return 1
  assert_equal "$(command -v "${path##*/}" || true)" "${path}" || return 1
}
