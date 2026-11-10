#!/usr/bin/env bash

set -euo pipefail

ssh_dir="${HOME}/.ssh"
github_key_path="${ssh_dir}/github_ed25519"
ssh_config_path="${ssh_dir}/config"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" > /dev/null 2>&1; then
    echo "required command not found: ${command_name}" >&2
    exit 1
  fi
}

is_interactive() {
  [[ -t 0 && -t 1 ]]
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

prompt_yes_no() {
  local prompt_message="$1"
  local default_answer="${2:-no}"
  local reply

  if ! is_interactive; then
    return 1
  fi

  if ! read -r -p "${prompt_message} " reply; then
    return 1
  fi

  if [[ -z ${reply} ]]; then
    is_yes "${default_answer}"
    return
  fi

  is_yes "${reply}"
}

source_nix() {
  if command -v nix > /dev/null 2>&1; then
    return
  fi

  if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # Official multi-user installs expose Nix through this profile script.
    # shellcheck source=/dev/null
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # Fallback for single-user installs.
    # shellcheck source=/dev/null
    . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  fi

  if ! command -v nix > /dev/null 2>&1; then
    echo 'nix is installed but was not added to PATH in the current shell.' >&2
    exit 1
  fi
}

ensure_nix() {
  local installer_script=''

  if command -v nix > /dev/null 2>&1; then
    return
  fi

  if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ||
    -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
    source_nix
    return
  fi

  require_command curl
  require_command sh

  installer_script="$(curl --proto '=https' --tlsv1.2 --fail -L https://nixos.org/nix/install)"
  sh -c "${installer_script}" nix-install --daemon
  source_nix
}

is_systemd_available() {
  [[ -d /run/systemd/system ]] && command -v systemctl > /dev/null 2>&1
}

resolve_nix_daemon_path() {
  if command -v nix-daemon > /dev/null 2>&1; then
    command -v nix-daemon
    return 0
  fi

  if [[ -x /nix/var/nix/profiles/default/bin/nix-daemon ]]; then
    printf '%s\n' '/nix/var/nix/profiles/default/bin/nix-daemon'
    return 0
  fi

  return 1
}

start_nix_daemon_without_systemd() {
  local nix_daemon_path=''

  if is_systemd_available; then
    return
  fi

  if pgrep --exact nix-daemon > /dev/null 2>&1; then
    return
  fi

  if ! nix_daemon_path="$(resolve_nix_daemon_path)"; then
    echo 'warning: nix-daemon binary was not found. Nix commands may fail in no-systemd environments.' >&2
    return
  fi

  if [[ ${EUID} -eq 0 ]]; then
    setsid "${nix_daemon_path}" --daemon > /dev/null 2>&1 &
  elif command -v sudo > /dev/null 2>&1; then
    if [[ -t 0 ]]; then
      if ! sudo --validate; then
        echo 'warning: failed to authenticate via sudo. Nix commands may fail.' >&2
        return
      fi
    elif ! sudo --non-interactive true > /dev/null 2>&1; then
      echo 'warning: cannot start nix-daemon automatically (sudo requires a password in non-interactive mode).' >&2
      return
    fi
    sudo --non-interactive setsid "${nix_daemon_path}" --daemon > /dev/null 2>&1 &
  else
    echo 'warning: cannot start nix-daemon automatically (sudo is unavailable in a no-systemd environment).' >&2
    return
  fi

  for _ in {1..10}; do
    if nix --extra-experimental-features 'nix-command flakes' store info > /dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  echo 'warning: attempted to start nix-daemon, but it is not responding yet. Nix commands may fail.' >&2
}

issl_login_shell_link() {
  printf '%s\n' "${XDG_STATE_HOME:-${HOME}/.local/state}/issl/login-shell"
}

is_executable_file() {
  [[ -f $1 && -x $1 ]]
}

current_login_shell() {
  if command -v getent > /dev/null 2>&1; then
    getent passwd "${EUID}" | cut -d: -f7
    return 0
  fi

  if [[ -n ${SHELL-} ]]; then
    printf '%s\n' "${SHELL}"
    return 0
  fi

  return 1
}

etc_shells_entry() {
  local shell_path="$1"
  local last_char=''

  if [[ -s /etc/shells ]]; then
    last_char="$(tail -c1 /etc/shells)" || return 1
  fi
  if [[ -n ${last_char} ]]; then
    printf '\n%s\n' "${shell_path}"
  else
    printf '%s\n' "${shell_path}"
  fi
}

ensure_shell_listed_in_etc_shells() {
  local shell_path="$1"

  if grep -Fxq "${shell_path}" /etc/shells 2> /dev/null; then
    return 0
  fi

  if [[ -w /etc/shells ]]; then
    if etc_shells_entry "${shell_path}" >> /etc/shells; then
      return 0
    fi
    echo "warning: failed to append ${shell_path} to /etc/shells directly." >&2
  fi

  if command -v sudo > /dev/null 2>&1; then
    if etc_shells_entry "${shell_path}" | sudo tee -a /etc/shells > /dev/null; then
      return 0
    fi
    echo "warning: failed to add ${shell_path} to /etc/shells via sudo. Skipping login shell registration." >&2
    return 1
  fi

  echo 'warning: /etc/shells is not writable and sudo is unavailable. Skipping login shell registration.' >&2
  return 1
}

maybe_register_login_shell() {
  local link=''
  local active_login_shell=''
  local user_name=''

  link="$(issl_login_shell_link)"
  active_login_shell="$(current_login_shell || true)"
  if [[ ${active_login_shell} == "${link}" ]] && is_executable_file "${link}"; then
    return
  fi

  if ! prompt_yes_no "Let Home Manager manage your login shell through ${link}? [Y/n]" yes; then
    return
  fi

  if ! is_executable_file "${link}"; then
    mkdir -p "$(dirname "${link}")" || true
    ln -Tsf /bin/bash "${link}" || true
  fi

  if ! is_executable_file "${link}"; then
    echo "warning: ${link} is not an executable file. Skipping the login shell registration." >&2
    return
  fi

  if ! ensure_shell_listed_in_etc_shells "${link}"; then
    return
  fi

  if ! user_name="$(id -un)"; then
    echo 'warning: could not determine the current user name. Skipping the login shell registration.' >&2
    return
  fi

  if sudo chsh --shell="${link}" "${user_name}"; then
    echo "Login shell set to ${link}. This will apply to new login sessions."
  else
    echo "warning: failed to run chsh. You can retry manually with: sudo chsh -s ${link} ${user_name}" >&2
  fi
}

nix_with_openssh() {
  nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#openssh_gssapi --command "$@"
}

has_github_ssh_auth() {
  local ssh_output
  local ssh_status

  ssh_output="$(nix_with_openssh ssh -o ConnectTimeout=10 -T git@github.com 2>&1)" || ssh_status="$?"
  ssh_status="${ssh_status:-0}"

  if [[ ${ssh_status} -eq 1 ]] \
    && printf '%s\n' "${ssh_output}" | grep -Fq 'successfully authenticated'; then
    return 0
  fi

  return 1
}

ensure_ssh_directory() {
  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"
}

github_ssh_key_exists() {
  [[ -f ${github_key_path} && -f "${github_key_path}.pub" ]]
}

create_github_ssh_key() {
  local key_comment=''

  ensure_ssh_directory

  if ! read -r -p 'Enter an email/comment for the GitHub SSH key (optional): ' key_comment; then
    echo
  fi

  if [[ -n ${key_comment} ]]; then
    nix_with_openssh ssh-keygen -t ed25519 -C "${key_comment}" -f "${github_key_path}"
  else
    nix_with_openssh ssh-keygen -t ed25519 -f "${github_key_path}"
  fi
}

ensure_github_ssh_config() {
  ensure_ssh_directory

  if [[ -f ${ssh_config_path} ]] \
    && grep -Eq '^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]]+github\.com([[:space:]]|$)' "${ssh_config_path}"; then
    return
  fi

  {
    echo 'Host github.com'
    echo '  HostName github.com'
    echo '  User git'
    echo '  IdentityFile ~/.ssh/github_ed25519'
  } >> "${ssh_config_path}"
  chmod 600 "${ssh_config_path}"
}

prompt_github_ssh_registration() {
  echo 'Register the following public key in GitHub:'
  echo 'https://github.com/settings/keys'
  echo
  cat "${github_key_path}.pub"
  echo

  for _ in {1..3}; do
    if ! prompt_yes_no 'Have you registered the key in GitHub? Answer n to skip. [Y/n]' yes; then
      echo 'Skipping GitHub SSH setup. Re-run this script to set it up later.'
      return 0
    fi

    if has_github_ssh_auth; then
      echo 'GitHub SSH authentication succeeded.'
      return 0
    fi

    echo 'Could not authenticate to GitHub with this key yet.' >&2
  done

  echo 'GitHub SSH access is not available. Re-run this script after registering the key or resolving the SSH connection.' >&2
  return 0
}

prompt_github_ssh_setup() {
  if ! github_ssh_key_exists; then
    if ! prompt_yes_no "No GitHub SSH key was found at ${github_key_path}. Create one now? [y/N]"; then
      return
    fi

    create_github_ssh_key
  fi

  ensure_github_ssh_config

  if ! is_interactive; then
    echo 'Register the following public key in GitHub and re-run:' >&2
    echo "  ${github_key_path}.pub" >&2
    return
  fi

  prompt_github_ssh_registration
}

maybe_offer_github_ssh_setup() {
  if ! is_interactive; then
    return
  fi

  if has_github_ssh_auth; then
    return
  fi

  if ! prompt_yes_no 'Set up GitHub SSH access now for future private repository use? [Y/n]' yes; then
    return
  fi

  prompt_github_ssh_setup
}

# Print the distribution and suite of the Docker apt repository for this host, or fail if Docker Engine setup does not support it.
docker_apt_repository() {
  (
    distribution=''
    suite=''
    unset ID UBUNTU_CODENAME VERSION_CODENAME VERSION_ID

    if [[ -r /etc/os-release ]]; then
      # shellcheck source=/dev/null
      . /etc/os-release
    fi

    if [[ ${ID-} == 'ubuntu' || -n ${UBUNTU_CODENAME-} ]]; then
      distribution='ubuntu'
      suite="${UBUNTU_CODENAME:-${VERSION_CODENAME-}}"
    elif [[ ${ID-} == 'debian' && -n ${VERSION_ID-} ]]; then
      distribution='debian'
      suite="${VERSION_CODENAME-}"
    fi

    if [[ -z ${distribution} || -z ${suite} ]]; then
      return 1
    fi

    printf '%s %s\n' "${distribution}" "${suite}"
  )
}

should_install_docker() {
  if is_no "${ISSL_INSTALL_DOCKER-}"; then
    return 1
  fi

  if ! is_yes "${ISSL_INSTALL_DOCKER-}" && ! is_interactive; then
    return 1
  fi

  if ! docker_apt_repository > /dev/null; then
    echo 'warning: Docker Engine setup supports only Ubuntu, its derivatives, and Debian stable releases; skipping it. Install Docker Engine through your distribution if you need it.' >&2
    return 1
  fi

  if is_yes "${ISSL_INSTALL_DOCKER-}"; then
    return 0
  fi

  prompt_yes_no 'Install Docker Engine for local container execution? [Y/n]' yes
}

should_add_user_to_docker_group() {
  if is_no "${ISSL_ADD_USER_TO_DOCKER_GROUP-}"; then
    return 1
  fi

  if is_yes "${ISSL_ADD_USER_TO_DOCKER_GROUP-}"; then
    return 0
  fi

  return 0
}

target_docker_user() {
  if [[ -n ${SUDO_USER-} && ${SUDO_USER} != 'root' ]]; then
    printf '%s\n' "${SUDO_USER}"
  elif [[ -n ${USER-} ]]; then
    printf '%s\n' "${USER}"
  else
    id -un
  fi
}

install_docker_engine() {
  local apt_keyrings_dir='/etc/apt/keyrings'
  local docker_user=''
  local repository=''
  local distribution=''
  local suite=''
  local architecture=''

  require_command sudo
  require_command apt-get
  require_command dpkg

  repository="$(docker_apt_repository)"
  distribution="${repository%% *}"
  suite="${repository#* }"

  sudo apt-get update
  sudo apt-get --yes install ca-certificates curl gnupg
  require_command curl
  require_command gpg
  sudo install -m 0755 -d "${apt_keyrings_dir}"

  curl --fail --location --show-error --silent "https://download.docker.com/linux/${distribution}/gpg" \
    | gpg --dearmor \
    | sudo tee "${apt_keyrings_dir}/docker.gpg" > /dev/null
  sudo chmod a+r "${apt_keyrings_dir}/docker.gpg"

  architecture="$(dpkg --print-architecture)"
  printf 'deb [arch=%s signed-by=%s/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
    "${architecture}" "${apt_keyrings_dir}" "${distribution}" "${suite}" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get --no-install-recommends --yes install docker-ce docker-ce-cli containerd.io pigz

  if should_add_user_to_docker_group; then
    docker_user="$(target_docker_user)"
    sudo usermod --append --groups=docker "${docker_user}"
    echo "Added ${docker_user} to the docker group."
    echo "Log out and back in, or run 'newgrp docker', before using Docker without sudo."
  fi

  if command -v systemctl > /dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    sudo systemctl enable --now docker.service
  fi
}

maybe_install_docker_engine() {
  if ! should_install_docker; then
    return
  fi

  install_docker_engine
}

bootstrap_host() {
  ensure_nix
  start_nix_daemon_without_systemd
  maybe_register_login_shell
  maybe_offer_github_ssh_setup
  maybe_install_docker_engine
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  bootstrap_host
fi
