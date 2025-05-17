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
MANIFEST = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"


def get_loader_versions():
    """
    Returns a list of the Neoforge loader version that should be packaged.
    """
    logger.info("Fetching loader versions")
    data = requests.get(
        f"{MAVEN}/api/maven/versions/releases/net/neoforged/neoforge"
    ).json()
    versions = [version for version in data["versions"] if not "beta" in version]
    return versions


def get_loader_game_version(loader_version):
    loader_parts = loader_version.split(".")
    return ".".join(["1"] + loader_parts[: (2 if loader_parts[1] != "0" else 1)])


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


def gen_loader_locks(logger, version):
    """
    Return the lock information for a given loader version
    """
    installer_url = f"{MAVEN}/releases/net/neoforged/neoforge/{version}/neoforge-{version}-installer.jar"

    ret = {
        "installer": {
            "url": installer_url,
            "sha256": requests.get(installer_url + ".sha256").text,
        },
        "mappings": get_mapping_artifact(get_loader_game_version(version)),
    }

    return ret


def main(versions_loader, loader_locks):
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
                loader_logger.info(f"Fetching version: {loader_version}")
                versions_loader[loader_version] = gen_loader_locks(
                    loader_logger,
                    loader_version,
                )
            else:
                loader_logger.info(f"Version {loader_version} already locked")
    except KeyboardInterrupt:
        logger.warning("Cancelled fetching, writing and exiting")

    json.dump(versions_loader, loader_locks, indent=2)
    loader_locks.write("\n")


if __name__ == "__main__":
    folder = Path(__file__).parent
    lock_file = folder / "lock.json"
    lock_file.touch()

    build_support_folder = folder.parent / "build-support"

    with (open(lock_file, "r") as loader_locks,):
        versions = {} if lock_file.stat().st_size == 0 else json.load(loader_locks)

    with (open(lock_file, "w") as loader_locks,):
        main(versions, loader_locks)
