{
  pkgs,
  lib,
  zip,
  unzip,
  fetchurl,
  stdenvNoCC,
  loader,
  loaderVersion,
  gameVersion,
  minecraft-server,
  jre_headless,
  extraJavaArgs ? "",
  extraMinecraftArgs ? "",
}:

let
  installer = fetchurl { inherit (loader.installer) url sha256; };
  mappings = fetchurl { inherit (loader.mappings) url sha1; };
  installerProfile = lib.importJSON "${
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
      '';

      installPhase = ''
        mkdir $out
        cp install_profile.json $out/install_profile.json
      '';

      phases = [
        "unpackPhase"
        "installPhase"
      ];
    }
  }/install_profile.json";
  installerDependencies = installerProfile.libraries;
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

  neoForgeServer = stdenvNoCC.mkDerivation rec {
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

    runScript = ''
      #!${pkgs.bash}/bin/bash
      exec ${lib.getExe jre_headless} $@ -jar 
    '';

    buildPhase = ''
      # Copy the installer
      cp ${installer} ./installer.jar

      # Install all libraries required by the installer
      ${installerLibrariesScript}

      # Add the mappings into the installer Jar
      mkdir -p ./maven/minecraft/${gameVersion}
      cp ${mappings} ./maven/minecraft/${gameVersion}/server_mappings.txt
      jar -uf ./installer.jar ./maven/minecraft/${gameVersion}/server_mappings.txt

      # Add the server jar to the libraries
      mkdir -p ./install/libraries/net/minecraft/server/${gameVersion}
      cp ${minecraft-server}/lib/minecraft/server.jar ./install/libraries/net/minecraft/server/${gameVersion}/server-${gameVersion}.jar

      # Run the installer
      java -jar ./installer.jar --install-server ./install --offline
    '';

    installPhase = ''
      mkdir $out
      cp -r ./install/** $out/
    '';

    phases = [
      "buildPhase"
      "installPhase"
    ];
  };

  argsFile = pkgs.writeText "neoforge-server-args" (
    lib.replaceStrings [ "libraries" ] [ "${neoForgeServer}/libraries" ] (
      lib.readFile "${neoForgeServer}/libraries/net/neoforged/neoforge/${loaderVersion}/unix_args.txt"
    )
  );
in
(pkgs.writeShellScriptBin "minecraft-server" ''
  exec ${lib.getExe jre_headless} ${extraJavaArgs} @${argsFile} "$@" ${extraMinecraftArgs}
'')
// rec {
  name = "${pname}-${version}";
  pname = "minecraft-server";
  version = "neoforge-${loaderVersion}";
}
