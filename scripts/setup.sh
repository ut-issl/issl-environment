#!/usr/bin/env bash

set -euo pipefail

default_repo_ref='v0.11.2'
default_bootstrap_repository_path='ut-issl/issl-environment'
repo_url="${REPO_URL:-https://github.com/ut-issl/issl-environment.git}"
repo_ref="${REPO_REF:-${default_repo_ref}}"
data_root="${XDG_DATA_HOME:-${HOME}/.local/share}"
install_dir="${INSTALL_DIR:-${data_root}/issl/environment}"

github_repository_path() {
  local path=''
  local owner=''
  local repo=''

  case "${repo_url}" in
  https://github.com/*)
    path="${repo_url#https://github.com/}"
    ;;
  git@github.com:*)
    path="${repo_url#git@github.com:}"
    ;;
  ssh://git@github.com/*)
    path="${repo_url#ssh://git@github.com/}"
    ;;
  *)
    echo "unsupported GitHub repository URL for bootstrap download: ${repo_url}" >&2
    exit 1
    ;;
  esac

  path="${path%.git}"
  if [[ ${path} == "${path#*/}" ]]; then
    echo "unsupported GitHub repository URL for bootstrap download: ${repo_url}" >&2
    exit 1
  fi

  owner="${path%%/*}"
  repo="${path#*/}"
  repo="${repo%%/*}"

  if [[ -z ${owner} || -z ${repo} ]]; then
    echo "unsupported GitHub repository URL for bootstrap download: ${repo_url}" >&2
    exit 1
  fi

  printf '%s/%s\n' "${owner}" "${repo}"
}

bootstrap_repository_path() {
  case "${repo_url}" in
  git@github.com:* | ssh://git@github.com/*)
    printf '%s\n' "${default_bootstrap_repository_path}"
    ;;
  *)
    github_repository_path
    ;;
  esac
}

bootstrap_ref() {
  if [[ -n ${BOOTSTRAP_REF-} ]]; then
    printf '%s\n' "${BOOTSTRAP_REF}"
    return
  fi

  case "${repo_url}" in
  git@github.com:* | ssh://git@github.com/*)
    printf '%s\n' "${default_repo_ref}"
    ;;
  *)
    printf '%s\n' "${repo_ref}"
    ;;
  esac
}

raw_bootstrap_url() {
  local bootstrap_ref_value
  local repository_path

  bootstrap_ref_value="$(bootstrap_ref)"
  repository_path="$(bootstrap_repository_path)"

  printf 'https://raw.githubusercontent.com/%s/%s/scripts/bootstrap-host.sh\n' "${repository_path}" "${bootstrap_ref_value}"
}

release_bootstrap_url() {
  local bootstrap_ref_value
  local repository_path

  bootstrap_ref_value="$(bootstrap_ref)"
  repository_path="$(bootstrap_repository_path)"

  printf 'https://github.com/%s/releases/download/%s/bootstrap-host.sh\n' "${repository_path}" "${bootstrap_ref_value}"
}

default_bootstrap_urls() {
  case "$(bootstrap_ref)" in
  v*)
    release_bootstrap_url
    raw_bootstrap_url
    ;;
  *)
    raw_bootstrap_url
    ;;
  esac
}

load_bootstrap_host() {
  local bootstrap_url=''
  local bootstrap_urls=''
  local script_dir=''
  local temporary_bootstrap=''

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

  if [[ -f "${script_dir}/bootstrap-host.sh" ]]; then
    # shellcheck source=scripts/bootstrap-host.sh
    . "${script_dir}/bootstrap-host.sh"
    return
  fi

  bootstrap_urls="${BOOTSTRAP_URL:-$(default_bootstrap_urls)}"

  if ! command -v curl >/dev/null 2>&1; then
    echo 'required command not found: curl' >&2
    exit 1
  fi

  temporary_bootstrap="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${temporary_bootstrap}'" EXIT
  while IFS= read -r bootstrap_url; do
    [[ -n ${bootstrap_url} ]] || continue

    if curl --fail --location --output "${temporary_bootstrap}" --show-error --silent "${bootstrap_url}"; then
      # shellcheck source=/dev/null
      . "${temporary_bootstrap}"
      rm -f "${temporary_bootstrap}"
      return
    fi
  done <<<"${bootstrap_urls}"

  echo 'failed to download bootstrap-host.sh.' >&2
  exit 1
}

nix_with_git() {
  nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git nixpkgs#openssh_gssapi --command "$@"
}

nix_git() {
  nix_with_git git "$@"
}

can_access_repo() {
  nix_git ls-remote --exit-code "${repo_url}" "${repo_ref}" >/dev/null 2>&1
}

is_github_ssh_repo_url() {
  case "${repo_url}" in
  git@github.com:* | ssh://git@github.com/*)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

try_github_ssh_recovery() {
  if has_github_ssh_auth; then
    return 1
  fi

  prompt_github_ssh_setup

  if has_github_ssh_auth && can_access_repo; then
    return 0
  fi

  return 1
}

fail_repo_access() {
  cat >&2 <<EOF
failed to access ${repo_url}.
confirm that:
- if this is a GitHub SSH remote, your SSH key is registered with GitHub
- your account has access to the repository
- the repository ref exists: ${repo_ref}
EOF
  exit 1
}

ensure_repo_access() {
  if can_access_repo; then
    return
  fi

  if is_github_ssh_repo_url && try_github_ssh_recovery; then
    return
  fi

  fail_repo_access
}

clone_repo() {
  if [[ -e ${install_dir} ]]; then
    echo "install destination already exists: ${install_dir}" >&2
    exit 1
  fi

  nix_git clone --branch="${repo_ref}" --single-branch "${repo_url}" "${install_dir}"
}

run_install() {
  bash "${install_dir}/scripts/apply.sh"
}

main() {
  load_bootstrap_host
  bootstrap_host
  ensure_repo_access
  clone_repo
  run_install

  echo 'ISSL environment setup completed.'
  echo "Repository clone: ${install_dir}"
}

main "$@"
