#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.requests

import json
import requests
from pathlib import Path
from requests.adapters import HTTPAdapter, Retry

RELEASES_ENDPOINT = "https://maven.neoforged.net/releases/net/neoforged/neoforge"
API_ENDPOINT = (
    "https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge"
)

TIMEOUT = 5
RETRIES = 5


class TimeoutHTTPAdapter(HTTPAdapter):
    def __init__(self, *args, **kwargs):
        self.timeout = TIMEOUT
        if "timeout" in kwargs:
            self.timeout = kwargs["timeout"]
            del kwargs["timeout"]
        super().__init__(*args, **kwargs)

    def send(self, request, **kwargs):
        timeout = kwargs.get("timeout")
        if timeout is None:
            kwargs["timeout"] = self.timeout
        return super().send(request, **kwargs)


def make_client():
    http = requests.Session()
    retries = Retry(
        total=RETRIES, backoff_factor=1, status_forcelist=[429, 500, 502, 503, 504]
    )
    http.mount("https://", TimeoutHTTPAdapter(max_retries=retries))
    return http


def get_versions(client):
    print("Fetching game versions")
    data = client.get(API_ENDPOINT).json()
    return data["versions"]


def get_installer_hash(version, client):
    hash_url = f"{RELEASES_ENDPOINT}/{version}/neoforge-{version}-installer.jar.sha256"
    hash_response = client.get(hash_url).text
    return hash_response


def main(lock, client):
    output = {}
    print("Starting fetch")

    for version in get_versions(client):
        if "beta" not in version:
            installer_url = (
                f"{RELEASES_ENDPOINT}/{version}/neoforge-{version}-installer.jar"
            )
            installer_hash = get_installer_hash(version, client)
            output[version] = {
                "url": installer_url,
                "sha256": installer_hash,
            }

    json.dump(output, lock, indent=2)
    lock.write("\n")


if __name__ == "__main__":
    folder = Path(__file__).parent
    lock_path = folder / "lock.json"
    main(open(lock_path, "w"), make_client())
