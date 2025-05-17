#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.requests

import json
import subprocess
import requests
import logging
from pathlib import Path
from requests.adapters import HTTPAdapter, Retry


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

MAVEN = "https://maven.neoforged.net"
NEO_MAVEN = f"{MAVEN}/releases"
MOJANG_MAVEN = "https://libraries.minecraft.net"
MANIFEST = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"


def get_loader_versions():
    """
    Returns a list of the Neoforge loader version that should be packaged.
    """
    logger.info("Fetching loader versions")
    data = requests.get(
        f"{MAVEN}/api/maven/versions/releases/net/neoforged/neoforge"
    ).json()
    versions = [
        version for version in data["versions"] if version.startswith("21.1.172")
    ]
    return versions


def get_loader_game_version(loader_version):
    return ".".join(["1"] + loader_version.split(".")[:2])


def fetch_loader_version(loader_version):
    """
    Return the loader information for a given loader version
    """
    data = requests.get(
        f"{MAVEN}/releases/net/neoforged/neoforge/{loader_version}/neoforge-{loader_version}-moddev-config.json"
    ).json()
    return data


def get_library_data(library):
    """
    Return the URL for a given library.
    """
    maven = NEO_MAVEN

    if library.startswith("com.mojang"):
        maven = MOJANG_MAVEN

    ret = {
        "name": library,
        "url": maven,
    }
    return ret


def prefetch_libraries(logger, new_libraries, libraries):
    logger = logger.getChild("libraries")
    ret = []

    print(new_libraries)

    for library in new_libraries:
        library = get_library_data(library)
        name, url = library["name"], library["url"]

        if not name in libraries or any(not v for k, v in libraries[name].items()):
            logger.info(f"Fetching {name}")
            nameparts = name.split(":")
            ldir, lname, lversion = nameparts[:3]

            lfilename = (
                f"{lname}-{lversion}"
                if len(nameparts) == 3
                else f"{lname}-{lversion}-{nameparts[3]}"
            )
            lurl = "/".join(
                (
                    url.rstrip("/"),
                    ldir.replace(".", "/"),
                    lname,
                    lversion,
                    lfilename + ".jar",
                )
            )

            lhash = subprocess.run(
                ["nix-prefetch-url", lurl], capture_output=True, encoding="UTF-8"
            ).stdout.rstrip("\n")

            libraries[name] = {"name": lfilename + ".zip", "url": lurl, "sha256": lhash}
        else:
            logger.debug(f"Using cached {name}")

        ret.append(name)

    return ret


minecraft_manifest = {}


def get_minecraft_manifest():
    if minecraft_manifest == {}:
        logger.info("Fetching Minecraft manifest")
        data = requests.get(MANIFEST).json()["versions"]
        for version in data:
            minecraft_manifest[version["id"]] = version["url"]

    return minecraft_manifest


mapping_artifacts = {}


def get_mapping_artifact(game_version):
    if game_version not in mapping_artifacts:
        manifest = get_minecraft_manifest()
        version_manifest = requests.get(manifest[game_version]).json()
        server_mappings = version_manifest["downloads"]["server_mappings"]
        mapping_artifacts[game_version] = server_mappings

    return mapping_artifacts[game_version]


def gen_loader_locks(logger, version, versionData, libraries):
    """
    Return the lock information for a given loader version
    """
    installer_url = (
        f"{NEO_MAVEN}/net/neoforged/neoforge/{version}/neoforge-{version}-installer.jar"
    )

    ret = {
        "installer": {
            "url": installer_url,
            "sha256": requests.get(installer_url + ".sha256").text,
        },
        "mappings": get_mapping_artifact(get_loader_game_version(version)),
        "mainClass": versionData["runs"]["server"]["main"],
        "libraries": prefetch_libraries(logger, versionData["libraries"], libraries),
        "full": versionData,
    }

    return ret


def main(versions_loader, libraries, loader_locks, lib_locks):
    """
    Fetch the relevant information and update the lockfiles.
    `versions` and `libraries` are data from the existing files, while
    `locks` and `lib_locks` are file objects to be written to
    """
    loader_versions = get_loader_versions()

    logger.info("Starting fetch")
    try:
        logger.info("Fetching loader versions")
        loader_logger = logger.getChild("loader")
        for loader_version in loader_versions:
            if not versions_loader.get(loader_version, None):
                loader_logger.info(f"Fetchinf version: {loader_version}")
                versions_loader[loader_version] = gen_loader_locks(
                    loader_logger,
                    loader_version,
                    fetch_loader_version(loader_version),
                    libraries,
                )
            else:
                loader_logger.info(f"Version {loader_version} already locked")
    except KeyboardInterrupt:
        logger.warning("Cancelled fetching, writing and exiting")

    json.dump(versions_loader, loader_locks, indent=2)
    json.dump(libraries, lib_locks, indent=2)
    loader_locks.write("\n")
    lib_locks.write("\n")


if __name__ == "__main__":
    folder = Path(__file__).parent
    lock_file = folder / "lock.json"
    lock_file.touch()

    build_support_folder = folder.parent / "build-support"
    libraries_file = build_support_folder / "libraries.json"
    libraries_file.touch()

    with (
        open(lock_file, "r") as loader_locks,
        open(libraries_file, "r") as lib_locks,
    ):
        versions = {} if lock_file.stat().st_size == 0 else json.load(loader_locks)
        libraries = {} if libraries_file.stat().st_size == 0 else json.load(lib_locks)

    with (
        open(lock_file, "w") as loader_locks,
        open(libraries_file, "w") as lib_locks,
    ):
        main(versions, libraries, loader_locks, lib_locks)
