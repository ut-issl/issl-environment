{
  lib,
  stdenvNoCC,
  fetchurl,
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
  pname = "capsula";
  inherit (source) version;

  src = fetchurl {
    url = "https://github.com/${source.repository}/releases/download/v${finalAttrs.version}/capsula-${targets.${system}}.tar.gz";
    hash = source.hashes.${system};
  };

  installPhase = ''
    runHook preInstall

    install -D -m 0755 capsula "$out/bin/capsula"

    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Command-line tool that runs hooks before and after a command to capture and preserve the context of its execution";
    homepage = "https://www.space.t.u-tokyo.ac.jp/capsula/";
    changelog = "https://github.com/${source.repository}/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = with lib.licenses; [
      mit
      asl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "capsula";
    platforms = lib.attrNames source.hashes;
  };
})
