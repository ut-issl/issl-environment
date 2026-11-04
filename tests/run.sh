#!/usr/bin/env bash
set -euo pipefail

common_dir="$(cd -- "${COMMON_DIR:-$(dirname -- "${BASH_SOURCE[0]}")/..}" && pwd)"
export COMMON_DIR="${common_dir}"

for name in nix platform shell utils git dev codex agents docker cpp node python rust typst vim; do
  printf '\n=== tests/test-%s.sh ===\n' "${name}"
  "${common_dir}/tests/test-${name}.sh"
done
