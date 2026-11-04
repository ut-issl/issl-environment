#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME_DIR:?HOME_DIR is required}"
common_dir="${COMMON_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
module_dir="${common_dir}/home-modules/agents"
claude_rule_path="${home_dir}/.claude/rules/issl-environment.md"
codex_skill_dir="${home_dir}/.agents/skills/issl-environment"
codex_rules_path="${home_dir}/.codex/rules/issl.rules"

source "${common_dir}/tests/lib.sh"

# Assert the decision of the deployed Codex rules on a command.
_assert_execpolicy_decision() {
  local expected="$1"
  local decision
  shift

  decision="$(codex execpolicy check -r "${codex_rules_path}" -- "$@" | jq -r '.decision // "none"')"
  assert_equal "${decision}" "${expected}" || return 1
}

test_claude_rule_file() {
  cmp "${module_dir}/issl-environment.md" "${claude_rule_path}"
}

test_codex_skill_directory() {
  assert_symlink "${codex_skill_dir}"
  assert_file "${codex_skill_dir}/SKILL.md"
  grep -Fxq 'name: issl-environment' "${codex_skill_dir}/SKILL.md"
  grep -Fxq '# ISSL Environment' "${codex_skill_dir}/SKILL.md"
}

test_codex_rules_file() {
  local file_type
  file_type="$(stat -c %F "${codex_rules_path}")"
  assert_equal "${file_type}" 'regular file'
  cmp "${module_dir}/issl.rules" "${codex_rules_path}"
}

test_codex_rules_forbid_global_installs() {
  _assert_execpolicy_decision forbidden pip install requests
  _assert_execpolicy_decision forbidden pip3 install requests
  _assert_execpolicy_decision forbidden python3 -m pip install requests
  _assert_execpolicy_decision forbidden pipx install ruff
  _assert_execpolicy_decision forbidden poetry new demo
  _assert_execpolicy_decision forbidden poetry init
  _assert_execpolicy_decision forbidden uv tool install ruff
  _assert_execpolicy_decision forbidden npm install -g prettier
  _assert_execpolicy_decision forbidden npm i --global prettier
  _assert_execpolicy_decision forbidden npm -g install prettier
  _assert_execpolicy_decision forbidden cargo install ripgrep
  _assert_execpolicy_decision forbidden cargo binstall ripgrep
}

test_codex_rules_allow_project_dependencies() {
  _assert_execpolicy_decision none uv add requests
  _assert_execpolicy_decision none uv tool run ruff
  _assert_execpolicy_decision none uvx ruff
  _assert_execpolicy_decision none pip --version
  _assert_execpolicy_decision none pipx run ruff
  _assert_execpolicy_decision none poetry run pytest
  _assert_execpolicy_decision none npm install prettier
  _assert_execpolicy_decision none cargo add serde
}

main() {
  run_test test_claude_rule_file
  run_test test_codex_skill_directory
  run_test test_codex_rules_file
  run_test test_codex_rules_forbid_global_installs
  run_test test_codex_rules_allow_project_dependencies
}

main "$@"
