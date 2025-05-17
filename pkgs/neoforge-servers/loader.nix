{
  lib,
  mkForgeLoader,
  loaderVersion,
  gameVersion,
}:
let
  loader_lock = (lib.importJSON ./lock.json).${loaderVersion};
in
mkForgeLoader {
  loaderName = "neoforge";
  inherit loaderVersion gameVersion;
  serverLaunch = throw "Unknown";
  inherit (loader_lock) mainClass;
  libraries = loader_lock.libraries;
}
