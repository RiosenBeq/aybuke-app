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
