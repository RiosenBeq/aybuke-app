"""Minimal App Store Connect API client (ES256 JWT). Never prints the key.

Reads ASC_KEY_ID and ASC_ISSUER_ID from the environment and the private key
from ~/.appstoreconnect/private_keys/AuthKey_<id>.p8.
"""
import base64
import json
import os
import time
from pathlib import Path

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

BASE = "https://api.appstoreconnect.apple.com"
_token = {"value": None, "exp": 0}


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token() -> str:
    now = int(time.time())
    if _token["value"] and _token["exp"] - now > 60:
        return _token["value"]
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    pem = (Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8").read_bytes()
    key = serialization.load_pem_private_key(pem, password=None)
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}
    signing_input = f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(payload).encode())}"
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    _token["value"] = f"{signing_input}.{_b64(signature)}"
    _token["exp"] = now + 1100
    return _token["value"]


def request(method: str, path: str, **kwargs):
    url = path if path.startswith("http") else BASE + path
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token()}"
    if "json" in kwargs:
        headers["Content-Type"] = "application/json"
    response = requests.request(method, url, headers=headers, timeout=60, **kwargs)
    if response.status_code >= 400:
        raise RuntimeError(f"{method} {path} -> {response.status_code}: {response.text[:1500]}")
    return response.json() if response.content else {}


def get(path, **params):
    return request("GET", path, params=params or None)


def get_all(path, **params):
    """Follows `links.next` and returns every item in `data`."""
    items, included = [], []
    result = get(path, **params)
    while True:
        items.extend(result.get("data", []))
        included.extend(result.get("included", []))
        next_url = result.get("links", {}).get("next")
        if not next_url:
            break
        result = request("GET", next_url)
    return items, included


def post(path, body):
    return request("POST", path, json=body)


def patch(path, body):
    return request("PATCH", path, json=body)


def delete(path):
    return request("DELETE", path)


# MARK: - Which version record a script works on

APP_ID = "6822716008"  # Aybuke's Apple ID (AppConfig.json appStoreID)
PLATFORMS = {"ios": "IOS", "mac": "MAC_OS"}
# States in which a version's metadata, screenshots and previews can still change.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


def version_spec(argv):
    """`--version 1.1` (a version string, both platforms), `--version <id>` (one
    record, its own platform) or a comma list of both; None without the flag."""
    for index, arg in enumerate(argv):
        if arg.startswith("--version="):
            return arg.split("=", 1)[1]
        if arg == "--version":
            if index + 1 >= len(argv) or argv[index + 1].startswith("--"):
                raise SystemExit("--version needs a version string (1.1) or a version id")
            return argv[index + 1]
    return None


def _state(attributes):
    return attributes.get("appVersionState") or attributes.get("appStoreState") or "?"


def resolve_versions(spec=None, platforms=("ios", "mac")):
    """{"ios"|"mac": (id, versionString, state)} for the version records to work
    on: the ones `spec` names, else each platform's editable one. Stops when a
    platform has none, or more than one editable record."""
    chosen, strings = {}, []
    for item in [s.strip() for s in (spec or "").split(",") if s.strip()]:
        if len(item) == 36 and item.count("-") == 4:
            data = get(f"/v1/appStoreVersions/{item}")["data"]
            platform = next(k for k, v in PLATFORMS.items() if v == data["attributes"]["platform"])
            chosen[platform] = (item, data["attributes"]["versionString"], _state(data["attributes"]))
        else:
            strings.append(item)
    for platform in platforms:
        if platform in chosen:
            continue
        versions, _ = get_all(f"/v1/apps/{APP_ID}/appStoreVersions", **{"filter[platform]": PLATFORMS[platform]})
        if strings:
            found = [v for v in versions if v["attributes"]["versionString"] in strings]
        else:
            found = [v for v in versions if _state(v["attributes"]) in EDITABLE]
        if len(found) != 1:
            listed = ", ".join(f"{v['attributes']['versionString']} {_state(v['attributes'])} {v['id']}" for v in versions)
            raise SystemExit(f"{platform}: {len(found)} matching version records (want 1). Versions: {listed or 'none'}")
        v = found[0]
        chosen[platform] = (v["id"], v["attributes"]["versionString"], _state(v["attributes"]))
    for platform, (vid, string, state) in sorted(chosen.items()):
        flag = "" if state in EDITABLE else "  (not editable in this state)"
        print(f"{platform}: version {string} {state} {vid}{flag}")
    return {p: chosen[p] for p in platforms if p in chosen}


def editable_app_info():
    """The app info record that takes name and subtitle edits (the one not live)."""
    infos, _ = get_all(f"/v1/apps/{APP_ID}/appInfos")
    live = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO"}
    open_ = [i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) not in live]
    return (open_ or infos)[0]["id"]
