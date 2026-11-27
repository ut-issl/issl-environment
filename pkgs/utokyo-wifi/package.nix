{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  versionCheckHook,
}:

let
  source = lib.importJSON ./source.json;
  inherit (stdenvNoCC.hostPlatform) system;
  targets = {
    x86_64-linux = "x86_64-unknown-linux-musl";
    aarch64-linux = "aarch64-unknown-linux-musl";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "utokyo-wifi";
  inherit (source) version;

  src = fetchurl {
    url = "https://github.com/${source.repository}/releases/download/v${finalAttrs.version}/utokyo-wifi-${targets.${system}}.tar.xz";
    hash = source.hashes.${system};
  };

  nativeBuildInputs = [ installShellFiles ];

  installPhase = ''
    runHook preInstall

    install -D -m 0755 utokyo-wifi "$out/bin/utokyo-wifi"
    installShellCompletion --cmd utokyo-wifi \
      --bash <("$out/bin/utokyo-wifi" completions bash) \
      --fish <("$out/bin/utokyo-wifi" completions fish) \
      --zsh <("$out/bin/utokyo-wifi" completions zsh)

    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Unofficial command-line tool to manage NetworkManager connections for UTokyo Wi-Fi and eduroam";
    homepage = "https://github.com/${source.repository}";
    changelog = "https://github.com/${source.repository}/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = with lib.licenses; [
      mit
      asl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "utokyo-wifi";
    platforms = lib.attrNames source.hashes;
  };
})
