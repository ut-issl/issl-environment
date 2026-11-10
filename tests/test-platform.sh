#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
config_dir="${CONFIG_DIR:?CONFIG_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

source "${common_dir}/tests/lib.sh"

test_xdg_data_dirs_are_exported() {
  env -i \
    HOME="${home_dir}" \
    SHELL_ENV_PATH="${config_dir}/issl/shell/env.sh" \
    XDG_CONFIG_HOME="${config_dir}" \
    PATH='/usr/bin:/bin' \
    bash << 'EOF'
. "${SHELL_ENV_PATH}"
case ":${XDG_DATA_DIRS}:" in
*:"${HOME}/.nix-profile/share":*) ;;
*) exit 1 ;;
esac
case ":${XDG_DATA_DIRS}:" in
*:/var/lib/snapd/desktop:*) ;;
*) exit 1 ;;
esac
EOF
}

main() {
  run_test test_xdg_data_dirs_are_exported
}

main "$@"
