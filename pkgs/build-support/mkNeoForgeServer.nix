{
  pkgs,
  lib,
  zip,
  unzip,
  fetchurl,
  stdenvNoCC,
  loader,
  loaderVersion,
  minecraft-server,
  jre_headless,
  extraJavaArgs ? "",
  extraMinecraftArgs ? "",
}:

let
  lib_lock = lib.importJSON ./libraries.json;
  installer = fetchurl { inherit (loader) url sha256; };
  libraries = loader.libraries;
  fetchLibrary = library: fetchurl lib_lock.${library};
  installerDependencies = lib.importJSON "${
    pkgs.stdenvNoCC.mkDerivation rec {
      name = "${pname}-${version}";
      pname = "neoforge-installer-dependencies";
      version = loaderVersion;

      src = installer;

      nativeBuildInputs = [
        unzip
        zip
        pkgs.jq
      ];

      unpackPhase = ''
        cp $src ./installer.zip
        unzip -o ./installer.zip install_profile.json
        cat install_profile.json | jq ".libraries" > dependencies.json
      '';

      installPhase = ''
        mkdir $out
        cp dependencies.json $out/dependencies.json
      '';

      phases = [
        "unpackPhase"
        "installPhase"
      ];
    }
  }/dependencies.json";
  librariesScript = lib.concatStringsSep "\n" (
    map (
      library:
      let
        parts = lib.splitString ":" library;
        domain = lib.head parts;
        artifact = lib.tail parts;
        artifactName = lib.head artifact;
        artifactVersion = lib.head (lib.tail artifact);
        artifactVariant = if (lib.length artifact) > 2 then lib.last artifact else null;
        path =
          "./install/libraries/"
          + lib.concatStringsSep "/" [
            (lib.replaceStrings [ "." ] [ "/" ] domain)
            artifactName
            artifactVersion
          ];
        fileName =
          lib.concatStringsSep "-" (
            [
              artifactName
              artifactVersion
            ]
            ++ lib.optional (artifactVariant != null) artifactVariant
          )
          + ".jar";
        filePath = path + "/" + fileName;
        file = fetchLibrary library;
      in
      ''
        mkdir -p ${path}
        cp ${file} ${filePath}
      ''
    ) libraries
  );
  installerLibrariesScript = lib.concatStringsSep "\n" (
    map (
      library:
      let
        artifact = library.downloads.artifact;
        libFile = fetchurl {
          url = artifact.url;
          sha1 = artifact.sha1;
        };
        filePath = "./install/libraries/" + artifact.path;
      in
      ''
        mkdir -p $(dirname ${filePath})
        cp ${libFile} ${filePath}
      ''
    ) installerDependencies
  );
in
stdenvNoCC.mkDerivation rec {
  name = "${pname}-${version}";
  pname = "neoforge-server";
  version = loaderVersion;
  nativeBuildInputs = [
    unzip
    zip
    jre_headless
    pkgs.tree
    pkgs.strace
  ];

  buildPhase = ''
    # mkdir -p ./install/libraries
    # echo $libraries
    # for i in ''${!libraries[@]}; do
    #   echo $i
    #   # unzip -o $i -d ./install/libraries/
    # done
    # false
    #''${librariesScript}
    ${installerLibrariesScript}

    mkdir -p ./install/libraries/net/minecraft/server/1.21.1
    cp ${minecraft-server}/lib/minecraft/server.jar ./install/libraries/net/minecraft/server/1.21.1/server-1.21.1.jar

    cp ${installer} ./installer.jar
    java -jar ./installer.jar --help
    # strace -f -t -e trace=file java -jar ./installer.jar --install-server ./install --offline
    java -jar ./installer.jar --install-server ./install --offline
  '';

  installPhase = ''
    mkdir $out
    cp -r . $out
  '';

  phases = [
    "buildPhase"
    "installPhase"
  ];

  passthru = {
  };
}
