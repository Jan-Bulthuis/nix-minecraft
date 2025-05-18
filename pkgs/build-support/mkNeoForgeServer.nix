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

  installerData = pkgs.stdenvNoCC.mkDerivation rec {
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
      unzip -o ./installer.zip install_profile.json version.json data/unix_args.txt
    '';

    installPhase = ''
      mkdir $out
      cp install_profile.json $out/install_profile.json
      cp version.json $out/version.json
      cp data/unix_args.txt $out/unix_args.txt
    '';

    phases = [
      "unpackPhase"
      "installPhase"
    ];
  };

  installerProfile = lib.importJSON "${installerData}/install_profile.json";
  installerVersion = lib.importJSON "${installerData}/version.json";
  installerDependencies = installerProfile.libraries ++ installerVersion.libraries;
  installerUnixArgs = lib.readFile "${installerData}/unix_args.txt";
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
        cp -n ${libFile} ${filePath}
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
      ${pkgs.unzip}/bin/unzip -o ./installer.jar -d ./installer
      java -jar ./installer.jar --install-server ./install --offline
    '';

    installPhase = ''
      mkdir $out
      cp -r ./install/** $out/

      mkdir $out/all
      cp -r ./** $out/all/
    '';

    phases = [
      "buildPhase"
      "installPhase"
    ];
  };

  argsFile = pkgs.writeText "neoforge-server-args" (
    lib.replaceStrings [ "libraries" ] [ "${neoForgeServer}/libraries" ] installerUnixArgs
  );
in
(pkgs.writeShellScriptBin "minecraft-server" ''
  exec ${lib.getExe jre_headless} ${extraJavaArgs} @${argsFile} ${extraMinecraftArgs}
'')
// rec {
  name = "${pname}-${version}";
  pname = "minecraft-server";
  version = "neoforge-${loaderVersion}";
}
