{
  lib,
  mkNeoForgeServer,
  vanillaServers,
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
      gameVersion = gameVersion;
      minecraft-server = vanillaServers."vanilla-${escapeVersion gameVersion}";
      extraJavaArgs = "";
      extraMinecraftArgs = "";
    });

  loaderVersions = lib.attrNames lock;
  packagesRaw = lib.genAttrs loaderVersions mkServer;
  packages = lib.mapAttrs' (
    version: drv: lib.nameValuePair "neoforge-${escapeVersion version}" drv
  ) packagesRaw;

in
lib.recurseIntoAttrs (
  packages
  // {
    neoforge = builtins.getAttr "neoforge-${escapeVersion latestLoaderVersion}" packages;
  }
)
