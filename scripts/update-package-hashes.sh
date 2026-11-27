#!/usr/bin/env bash

# Recompute the hashes in pkgs/<name>/source.json for each package named as an argument.
# Each hash is that of the file that fetchurl downloads as src;
# a source that is unpacked before hashing, such as fetchFromGitHub, is not supported.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

update_package_hashes() {
  local name="$1"
  local source_path="${repo_root}/pkgs/${name}/source.json"
  local systems_output=''
  local systems=()
  local system=''
  local url=''
  local hash=''
  local updated_source=''

  if [[ ! -f ${source_path} ]]; then
    echo "error: ${source_path} does not exist." >&2
    exit 1
  fi

  systems_output="$(jq --raw-output '.hashes | keys_unsorted[]' "${source_path}")"
  if [[ -z ${systems_output} ]]; then
    echo "error: ${source_path} lists no system under hashes." >&2
    exit 1
  fi
  mapfile -t systems <<< "${systems_output}"
  for system in "${systems[@]}"; do
    url="$(nix eval --raw "${repo_root}#packages.${system}.${name}.src.url")"
    hash="$(nix store prefetch-file --json "${url}" | jq --raw-output --exit-status '.hash')"
    updated_source="$(jq --ascii-output --arg system "${system}" --arg hash "${hash}" '.hashes[$system] = $hash' \
      "${source_path}")"
    printf '%s\n' "${updated_source}" > "${source_path}"
    echo "${name} (${system}): ${hash}"
  done
}

main() {
  local name=''

  if [[ $# -eq 0 ]]; then
    echo "usage: $0 <name>..." >&2
    exit 1
  fi

  for name in "$@"; do
    update_package_hashes "${name}"
  done
}

main "$@"
