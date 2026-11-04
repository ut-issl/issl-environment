{
  config,
  lib,
  pkgs,
  ...
}:

let
  codexHome = config.home.sessionVariables.CODEX_HOME or "${config.home.homeDirectory}/.codex";

  environmentSkill = pkgs.writeTextDir "SKILL.md" ''
    ---
    name: issl-environment
    description: >-
      Practices of the ISSL shared environment for installing software.
      Use before installing a tool, a package, or a dependency,
      such as with pip, uv, npm, cargo, apt, or Nix.
    ---

    ${builtins.readFile ./issl-environment.md}
  '';
in
{
  home.file = {
    "${config.programs.claude-code.configDir}/rules/issl-environment.md".source = ./issl-environment.md;
    ".agents/skills/issl-environment".source = environmentSkill;
  };

  home.activation.installCodexRules = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run install -D -m 0444 ${./issl.rules} "${codexHome}/rules/issl.rules"
  '';
}
