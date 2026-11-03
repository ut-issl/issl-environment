#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "${repo_root}/scripts/bootstrap-host.sh"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"

issl_config_home="${XDG_CONFIG_HOME}/issl"
shared_nix_config_path="${issl_config_home}/nix/nix.conf"
shared_shell_env_path="${issl_config_home}/shell/env.sh"
shared_bashrc_path="${issl_config_home}/bash/.bashrc"
shared_zprofile_path="${issl_config_home}/zsh/.zprofile"
shared_zshrc_path="${issl_config_home}/zsh/.zshrc"
shared_git_config_path="${issl_config_home}/git/.gitconfig"
shared_rust_config_path="${issl_config_home}/rust/config.toml"
git_user_name="${GIT_USER_NAME-}"
git_user_email="${GIT_USER_EMAIL-}"
issl_enable_zsh="${ISSL_ENABLE_ZSH-}"
nix_feature_config='experimental-features = nix-command flakes'
hm_profile_dir="${XDG_STATE_HOME}/nix/profiles"

# ===== Common ===== #

ensure_home_manager_profile_dir() {
  mkdir -p "${hm_profile_dir}"
}

resolves_into_nix_store() {
  local path="$1"
  local resolved_path=''

  resolved_path="$(readlink -m "${path}")" || return 1
  case "${resolved_path}" in
  /nix/store/*) return 0 ;;
  *) return 1 ;;
  esac
}

guard_against_existing_home_manager_files() {
  local zsh_enabled="$1"
  local zdotdir_path="${XDG_CONFIG_HOME}/zsh"
  local cargo_home_path="${CARGO_HOME:-${HOME}/.cargo}"
  local zshenv_path="${HOME}/.zshenv"
  local resolved_zdotdir=''
  local candidate_path=''
  local managed_paths=()

  if zshenv_defines_zdotdir "${zshenv_path}"; then
    if resolved_zdotdir="$(resolve_zdotdir_from_zshenv "${zshenv_path}")"; then
      zdotdir_path="${resolved_zdotdir}"
    elif [[ ${zsh_enabled} == '1' ]] && resolve_zsh_bin >/dev/null; then
      echo "error: ${zshenv_path} defines ZDOTDIR, but it could not be resolved before the Home Manager switch." >&2
      echo "Fix ${zshenv_path} so that zsh can evaluate it, or re-run with ISSL_ENABLE_ZSH=no to skip the zsh setup." >&2
      exit 1
    fi
  fi

  local candidate_paths=(
    "${XDG_CONFIG_HOME}/nix/nix.conf"
    "${HOME}/.profile"
    "${HOME}/.bash_profile"
    "${HOME}/.bashrc"
    "${HOME}/.zshenv"
    "${zdotdir_path}/.zprofile"
    "${zdotdir_path}/.zshrc"
    "${HOME}/.gitconfig"
    "${XDG_CONFIG_HOME}/git/config"
    "${XDG_CONFIG_HOME}/python/pythonrc.py"
    "${cargo_home_path}/config.toml"
  )

  for candidate_path in "${candidate_paths[@]}"; do
    if resolves_into_nix_store "${candidate_path}"; then
      managed_paths+=("${candidate_path}")
    fi
  done

  if [[ ${#managed_paths[@]} -eq 0 ]]; then
    return
  fi

  {
    echo 'error: the following files resolve into the Nix store, so this machine already appears to be managed by an existing Home Manager configuration:'
    printf '  %s\n' "${managed_paths[@]}"
    echo "Running the script-based setup here would replace that configuration's Home Manager profile and detach these files from its control."
    echo 'Keep managing this machine with your existing Home Manager configuration (e.g. your personal config repository) instead.'
    echo 'If you really want to switch to the script-based setup, remove the existing Home Manager configuration first and re-run this script.'
  } >&2
  exit 1
}

# Create the parent directory, report whether the block still has to be written,
# and refuse a file that Home Manager manages.
prepare_block_file() {
  local file_path="$1"
  local begin_marker="$2"

  mkdir -p "$(dirname "${file_path}")"

  if [[ -f ${file_path} ]] && grep -Fq "${begin_marker}" "${file_path}"; then
    return 1
  fi

  if resolves_into_nix_store "${file_path}"; then
    echo "error: refusing to modify ${file_path} because it resolves into the Nix store (likely managed by Home Manager)." >&2
    exit 1
  fi
}

prepend_block_once() {
  local file_path="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local block_content="$4"
  local temp_file=''

  prepare_block_file "${file_path}" "${begin_marker}" || return 0

  touch "${file_path}"

  local original_mode=''
  original_mode="$(stat -L -c %a "${file_path}")"

  temp_file="$(mktemp)"
  {
    printf '%s\n' "${begin_marker}"
    printf '%s\n' "${block_content}"
    printf '%s\n' "${end_marker}"
    if [[ -s ${file_path} ]]; then
      printf '\n'
      cat "${file_path}"
    fi
  } >"${temp_file}"
  mv "${temp_file}" "${file_path}"
  chmod "${original_mode}" "${file_path}"
}

# Reduce the file to the block alone, keeping any previous content at <file>.backup.
replace_with_block_once() {
  local file_path="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local block_content="$4"
  local backup_path=''
  local temp_file=''

  prepare_block_file "${file_path}" "${begin_marker}" || return 0

  touch "${file_path}"

  local original_mode=''
  original_mode="$(stat -L -c %a "${file_path}")"

  if [[ -s ${file_path} ]]; then
    backup_path="${file_path}.backup"
    if [[ -e ${backup_path} || -L ${backup_path} ]]; then
      echo "error: refusing to replace ${file_path} because ${backup_path} already exists." >&2
      echo "Move or remove ${backup_path} and re-run this script." >&2
      exit 1
    fi
  fi

  # Build the replacement beside the target so that moving it into place is a same-filesystem rename.
  temp_file="$(mktemp "${file_path}.XXXXXX")"
  {
    printf '%s\n' "${begin_marker}"
    printf '%s\n' "${block_content}"
    printf '%s\n' "${end_marker}"
  } >"${temp_file}"

  if [[ -n ${backup_path} ]]; then
    mv "${file_path}" "${backup_path}"
    echo "Replaced ${file_path} with the shared configuration and kept the previous file at ${backup_path}."
  fi

  mv "${temp_file}" "${file_path}"
  chmod "${original_mode}" "${file_path}"
}

is_yes() {
  case "${1-}" in
  y | Y | yes | YES | Yes | true | TRUE | True | 1) return 0 ;;
  *) return 1 ;;
  esac
}

is_no() {
  case "${1-}" in
  n | N | no | NO | No | false | FALSE | False | 0) return 0 ;;
  *) return 1 ;;
  esac
}

# ===== Nix ===== #

nix_conf_include_block() {
  printf '%s\n' "!include ${shared_nix_config_path}"
}

ensure_nix_conf_include() {
  local nix_config_dir="${XDG_CONFIG_HOME}/nix"
  local nix_config_path="${nix_config_dir}/nix.conf"
  local block_content=''

  mkdir -p "${nix_config_dir}"

  if [[ -f ${nix_config_path} ]] && grep -Fq "${shared_nix_config_path}" "${nix_config_path}"; then
    return
  fi

  block_content="$(nix_conf_include_block)"
  prepend_block_once \
    "${nix_config_path}" \
    '# >>> ISSL nix config >>>' \
    '# <<< ISSL nix config <<<' \
    "${block_content}"
}

# ===== Bash ===== #

profile_env_block() {
  printf '%s\n' \
    "if [ -f \"${shared_shell_env_path}\" ]; then" \
    "  . \"${shared_shell_env_path}\"" \
    'fi'
}

bash_profile_block() {
  # shellcheck disable=SC2016  # the block is emitted verbatim; $HOME, $-, and ${...} must stay literal.
  printf '%s\n' \
    'if [ -f "$HOME/.profile" ]; then' \
    '  . "$HOME/.profile"' \
    'fi' \
    'case $- in' \
    '*i*)' \
    '  if [ "${ISSL_BASHRC_LOADED:-0}" != "1" ] && [ -f "$HOME/.bashrc" ]; then' \
    '    . "$HOME/.bashrc"' \
    '  fi' \
    '  ;;' \
    'esac'
}

bashrc_block() {
  printf '%s\n' \
    "if [ -f \"${shared_bashrc_path}\" ]; then" \
    "  . \"${shared_bashrc_path}\"" \
    'fi'
}

ensure_bash_startup_files() {
  local block_content=''

  block_content="$(profile_env_block)"
  replace_with_block_once \
    "${HOME}/.profile" \
    '# >>> ISSL shell env >>>' \
    '# <<< ISSL shell env <<<' \
    "${block_content}"
  block_content="$(bash_profile_block)"
  prepend_block_once \
    "${HOME}/.bash_profile" \
    '# >>> ISSL bash profile >>>' \
    '# <<< ISSL bash profile <<<' \
    "${block_content}"
  block_content="$(bashrc_block)"
  replace_with_block_once \
    "${HOME}/.bashrc" \
    '# >>> ISSL bash rc >>>' \
    '# <<< ISSL bash rc <<<' \
    "${block_content}"
}

# ===== Zsh ===== #

should_enable_zsh() {
  local current_shell_name=''

  if [[ -n ${issl_enable_zsh} ]]; then
    if is_yes "${issl_enable_zsh}"; then
      return 0
    fi
    if is_no "${issl_enable_zsh}"; then
      return 1
    fi
    echo 'ISSL_ENABLE_ZSH must be a yes/no style value.' >&2
    exit 1
  fi

  current_shell_name="$(basename "${SHELL-}")"
  if [[ ${current_shell_name} == 'zsh' ]]; then
    return 0
  fi

  if ! is_interactive; then
    return 1
  fi

  prompt_yes_no 'Enable shared zsh configuration as well? [Y/n]' yes
}

zshenv_defines_zdotdir() {
  local zshenv_path="$1"

  [[ -f ${zshenv_path} ]] && grep -Eq '^[[:space:]]*(export[[:space:]]+)?ZDOTDIR[[:space:]]*=' "${zshenv_path}"
}

resolve_zdotdir_from_zshenv() {
  local zshenv_path="$1"
  local zsh_bin=''
  local resolved_value=''

  if [[ -x "${HOME}/.nix-profile/bin/zsh" ]]; then
    zsh_bin="${HOME}/.nix-profile/bin/zsh"
  elif command -v zsh >/dev/null 2>&1; then
    zsh_bin="$(command -v zsh)"
  else
    return 1
  fi

  # shellcheck disable=SC2016
  resolved_value="$(
    env -i \
      HOME="${HOME}" \
      XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
      ZDOTDIR='' \
      PATH=/usr/bin:/bin \
      "${zsh_bin}" -c '
        . "$1"
        if [ -n "${ZDOTDIR:-}" ]; then
          print -r -- "${ZDOTDIR:A}"
        fi
      ' _ "${zshenv_path}" </dev/null
  )"
  [[ -n ${resolved_value} ]] || return 1
  printf '%s\n' "${resolved_value}"
}

zshenv_default_block() {
  cat <<'ZSHENV_EOF'
if [ -z "${ZDOTDIR:-}" ]; then
  export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
fi
ZSHENV_EOF
}

zprofile_block() {
  printf '%s\n' \
    "if [ -f \"${shared_zprofile_path}\" ]; then" \
    "  . \"${shared_zprofile_path}\"" \
    'fi'
}

zshrc_block() {
  printf '%s\n' \
    "if [ -f \"${shared_zshrc_path}\" ]; then" \
    "  . \"${shared_zshrc_path}\"" \
    'fi'
}

ensure_zsh_startup_files() {
  local zshenv_path="${HOME}/.zshenv"
  local zdotdir_path=''
  local block_content=''

  if zshenv_defines_zdotdir "${zshenv_path}"; then
    if ! zdotdir_path="$(resolve_zdotdir_from_zshenv "${zshenv_path}")"; then
      echo "Could not determine ZDOTDIR from ${zshenv_path}." >&2
      exit 1
    fi
  else
    block_content="$(zshenv_default_block)"
    prepend_block_once \
      "${zshenv_path}" \
      '# >>> ISSL zsh env >>>' \
      '# <<< ISSL zsh env <<<' \
      "${block_content}"
    zdotdir_path="${XDG_CONFIG_HOME}/zsh"
  fi

  mkdir -p "${zdotdir_path}"
  block_content="$(zprofile_block)"
  prepend_block_once \
    "${zdotdir_path}/.zprofile" \
    '# >>> ISSL zsh profile >>>' \
    '# <<< ISSL zsh profile <<<' \
    "${block_content}"
  block_content="$(zshrc_block)"
  prepend_block_once \
    "${zdotdir_path}/.zshrc" \
    '# >>> ISSL zsh rc >>>' \
    '# <<< ISSL zsh rc <<<' \
    "${block_content}"
}

resolve_zsh_bin() {
  if [[ -x "${HOME}/.nix-profile/bin/zsh" ]]; then
    printf '%s\n' "${HOME}/.nix-profile/bin/zsh"
    return 0
  fi

  if command -v zsh >/dev/null 2>&1; then
    command -v zsh
    return 0
  fi

  return 1
}

# ===== Git ===== #

resolve_git_bin() {
  if [[ -x "${HOME}/.nix-profile/bin/git" ]]; then
    printf '%s\n' "${HOME}/.nix-profile/bin/git"
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    command -v git
    return 0
  fi

  return 1
}

ensure_git_include() {
  if ! "${git_bin}" config --global --get-all include.path | grep -Fxq "${shared_git_config_path}"; then
    "${git_bin}" config --global --add include.path "${shared_git_config_path}"
  fi
}

prompt_for_git_identity() {
  local git_name=''
  local git_email=''
  local missing_identity=0

  if ! git_name="$("${git_bin}" config --global --get user.name 2>/dev/null)" || [[ -z ${git_name} ]]; then
    if [[ -n ${git_user_name} ]]; then
      git_name="${git_user_name}"
    elif [[ -t 0 ]]; then
      read -r -p 'Enter your full name for Git commits: ' git_name
    else
      echo 'warning: Git user.name setup was skipped. Run with GIT_USER_NAME, or set it later with: git config --global user.name "Your Name"' >&2
      missing_identity=1
    fi
    if [[ -n ${git_name} ]]; then
      "${git_bin}" config --global user.name "${git_name}"
    fi
  fi

  if ! git_email="$("${git_bin}" config --global --get user.email 2>/dev/null)" || [[ -z ${git_email} ]]; then
    if [[ -n ${git_user_email} ]]; then
      git_email="${git_user_email}"
    elif [[ -t 0 ]]; then
      read -r -p 'Enter your email address for Git commits: ' git_email
    else
      echo 'warning: Git user.email setup was skipped. Run with GIT_USER_EMAIL, or set it later with: git config --global user.email "you@example.com"' >&2
      missing_identity=1
    fi
    if [[ -n ${git_email} ]]; then
      "${git_bin}" config --global user.email "${git_email}"
    fi
  fi

  if [[ ${missing_identity} == '1' ]]; then
    echo 'warning: Git identity was not configured. Environment variables were not provided, and this run is non-interactive so prompts could not be used. Pass the env vars, run interactively, or set it later.' >&2
  fi
}

# ===== Python ===== #

pythonrc_block() {
  cat <<'PYTHON_EOF'
import os
from pathlib import Path
import runpy

issl_python_home = os.environ.get("ISSL_PYTHON_HOME")
if not issl_python_home:
  config_home = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
  issl_python_home = str(Path(config_home) / "issl" / "python")

shared_pythonrc = Path(issl_python_home) / "pythonrc.py"
if shared_pythonrc.is_file():
  runpy.run_path(str(shared_pythonrc), run_name="__main__")
PYTHON_EOF
}

ensure_python_startup_file() {
  local block_content=''

  block_content="$(pythonrc_block)"
  prepend_block_once \
    "${XDG_CONFIG_HOME}/python/pythonrc.py" \
    '# >>> ISSL python startup >>>' \
    '# <<< ISSL python startup <<<' \
    "${block_content}"
}

# ===== Rust ===== #

cargo_config_include_block() {
  printf '%s\n' \
    'include = [' \
    "  { path = \"${shared_rust_config_path}\", optional = true }," \
    ']'
}

ensure_cargo_config_include() {
  local cargo_home_path="${CARGO_HOME:-${HOME}/.cargo}"
  local cargo_config_path="${cargo_home_path}/config.toml"
  local block_content=''

  mkdir -p "${cargo_home_path}"

  if [[ -f ${cargo_config_path} ]] && grep -Fq "${shared_rust_config_path}" "${cargo_config_path}"; then
    return
  fi

  if [[ -f ${cargo_config_path} ]] && grep -Eq '^[[:space:]]*include[[:space:]]*=' "${cargo_config_path}"; then
    echo "Skipping Cargo include setup because ${cargo_config_path} already defines include." >&2
    echo "Please add ${shared_rust_config_path} to include manually." >&2
    return
  fi

  block_content="$(cargo_config_include_block)"
  prepend_block_once \
    "${cargo_config_path}" \
    '# >>> ISSL cargo config >>>' \
    '# <<< ISSL cargo config <<<' \
    "${block_content}"
}

main() {
  if ! command -v nix >/dev/null 2>&1; then
    echo 'nix is required before running scripts/apply.sh.' >&2
    exit 1
  fi

  if should_enable_zsh; then
    zsh_enabled=1
  else
    zsh_enabled=0
  fi

  guard_against_existing_home_manager_files "${zsh_enabled}"

  if [[ -n ${NIX_CONFIG-} ]]; then
    export NIX_CONFIG="${NIX_CONFIG}"$'\n'"${nix_feature_config}"
  else
    export NIX_CONFIG="${nix_feature_config}"
  fi

  start_nix_daemon_without_systemd

  current_system="$(
    nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
      eval --raw --impure --expr builtins.currentSystem
  )"

  ensure_home_manager_profile_dir
  if [[ ${zsh_enabled} == '1' ]]; then
    home_configuration_name="common-${current_system}"
  else
    home_configuration_name="common-bash-only-${current_system}"
  fi

  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "${repo_root}#home-manager" -- \
    switch --flake "${repo_root}#${home_configuration_name}" --impure

  ensure_nix_conf_include
  ensure_bash_startup_files
  if [[ ${zsh_enabled} == '1' ]]; then
    ensure_zsh_startup_files
    maybe_register_login_shell
  fi
  if ! git_bin="$(resolve_git_bin)"; then
    echo 'git was not found after the Home Manager switch; cannot wire the shared Git configuration.' >&2
    exit 1
  fi
  ensure_git_include
  prompt_for_git_identity
  ensure_python_startup_file
  ensure_cargo_config_include

  echo 'Applied the shared Home Manager configuration.'
}

main "$@"
