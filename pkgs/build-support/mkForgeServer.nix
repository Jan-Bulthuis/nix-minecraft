{
  pkgs,
  callPackage,
  lib,
  writeShellScriptBin,
  minecraft-server,
  jre_headless,
  loaderVersion,
  loaderDrv,
  loader ? (
    callPackage loaderDrv {
      inherit loaderVersion;
      gameVersion = minecraft-server.version;
    }
  ),
  extraJavaArgs ? "",
  extraMinecraftArgs ? "",
}:
# (writeShellScriptBin "minecraft-server" ''exec ${lib.getExe jre_headless} ${extraJavaArgs} $@ -jar ${loader}/run.sh nogui ${extraMinecraftArgs}'')
(writeShellScriptBin "minecraft-server" ''
  ${pkgs.tree}/bin/tree ${loader}
  exec ${lib.getExe jre_headless} ${extraJavaArgs} $@ -jar ${loader} nogui ${extraMinecraftArgs}
'')
// rec {
  pname = "minecraft-server";
  version = "${minecraft-server.version}-${loader.loaderName}-${loader.loaderVersion}";
  name = "${pname}-${version}";

  passthru = {
    inherit loader;
  };
}
