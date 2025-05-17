{
  lib,
  fetchurl,
  stdenvNoCC,
  unzip,
  zip,
  jre_headless,
  loaderName,
  loaderVersion,
  gameVersion,
  serverLaunch,
  mainClass,
  libraries,
}:

let
  inherit (builtins)
    head
    filter
    map
    match
    ;

  lib_lock = lib.importJSON ./libraries.json;
  fetchedLibraries = lib.forEach libraries (l: fetchurl lib_lock.${l});
  asmVersion = head (
    head (filter (v: v != null) (map (match "org\\.ow2\\.asm:asm:([\.0-9]+)") libraries))
  );
in
stdenvNoCC.mkDerivation {
  pname = "${loaderName}-server-launch.jar";
  version = "${loaderName}-${loaderVersion}-${gameVersion}";
  nativeBuildInputs = [
    unzip
    zip
    jre_headless
  ];

  libraries = fetchedLibraries;

  buildPhase = ''
    for i in $libraries; do
      unzip -o $i
    done

    cat > META-INF/MANIFEST.MF << EOF
    Manifest-Version: 1.0
    Main-Class: ${mainClass}
    EOF
  '';

  installPhase = ''
    rm -f META-INF/*.{SF,RSA,DSA}
    jar cmvf META-INF/MANIFEST.MF "server.jar" .
    cp server.jar $out
  '';

  phases = [
    "buildPhase"
    "installPhase"
  ];

  passthru = {
    inherit loaderName loaderVersion gameVersion;
    propertyPrefix = loaderName;
  };
}
