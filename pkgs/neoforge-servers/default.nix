{
  lib,
  vanillaServers,
  mkNeoForgeServer,
}:

with lib;
let
  lock = lib.importJSON ./lock.json;

  inherit (lib.our) escapeVersion latestVersion;

  latestLoaderVersion = latestVersion lock;

  getGameVersion =
    loaderVersion: "1.${concatStringsSep "." (take 2 (splitString "." loaderVersion))}";

  mkServer =
    loaderVersion:
    let
      gameVersion = getGameVersion loaderVersion;
    in
    (mkNeoForgeServer {
      loaderVersion = loaderVersion;
      loader = lock.${loaderVersion};
      minecraft-server = vanillaServers."vanilla-${escapeVersion gameVersion}";
      extraJavaArgs = "";
      extraMinecraftArgs = "";
    });

in
lib.recurseIntoAttrs ({
  neoforge = mkServer latestLoaderVersion;
})
