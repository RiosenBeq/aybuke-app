"""Uploads the iPhone App Preview videos in docs/marketing/app-preview/ to the iOS
version: aybuke-app-preview-iphone-<lang>.mp4 goes to the locales in LOCALES[<lang>],
replacing that locale's previews of the same display type.

    asc_previews.py <repo> [--version 1.1] [--dry-run] [--only=en-US,tr]

--version takes a version string or a version id (see asc.resolve_versions);
without it, the editable iOS version. The poster frame is FRAME (the first
caption is on screen from the first frame).
"""
import hashlib
import sys
import time
from pathlib import Path

import requests

import asc

REPO = Path(sys.argv[1])
DRY = "--dry-run" in sys.argv
ONLY = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
FOLDER = REPO / "docs/marketing/app-preview"
PREVIEW_TYPE = "IPHONE_67"  # 886×1920 portrait serves the 6.9-inch and smaller iPhones
FRAME = "00:00:00:06"
LOCALES = {"en": ["en-US"], "tr": ["tr"]}


def preview_set(localization_id):
    sets, _ = asc.get_all(f"/v1/appStoreVersionLocalizations/{localization_id}/appPreviewSets")
    for item in sets:
        if item["attributes"]["previewType"] == PREVIEW_TYPE:
            return item["id"]
    created = asc.post("/v1/appPreviewSets", {"data": {
        "type": "appPreviewSets", "attributes": {"previewType": PREVIEW_TYPE},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}})
    return created["data"]["id"]


def upload(set_id, video):
    data = video.read_bytes()
    reserved = asc.post("/v1/appPreviews", {"data": {
        "type": "appPreviews",
        "attributes": {"fileName": video.name, "fileSize": len(data), "mimeType": "video/mp4", "previewFrameTimeCode": FRAME},
        "relationships": {"appPreviewSet": {"data": {"type": "appPreviewSets", "id": set_id}}}}})["data"]
    for op in reserved["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        for attempt in range(3):
            try:
                requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=300).raise_for_status()
                break
            except Exception as error:  # retry a dropped part
                print("  part retry", op["offset"], type(error).__name__)
                if attempt == 2:
                    raise
    asc.patch(f"/v1/appPreviews/{reserved['id']}", {"data": {
        "type": "appPreviews", "id": reserved["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    for _ in range(45):  # Apple processes the video for a few minutes
        state = (asc.get(f"/v1/appPreviews/{reserved['id']}")["data"]["attributes"].get("assetDeliveryState") or {})
        if state.get("state") in ("COMPLETE", "FAILED"):
            print("  ", state.get("state"), state.get("errors") or "")
            return
        time.sleep(20)
    print("   still processing; check App Store Connect")


def main():
    version, _, _ = asc.resolve_versions(asc.version_spec(sys.argv), platforms=("ios",), dry=DRY)["ios"]
    if version is None:  # dry run before the version exists
        by_locale = {locale: None for locales in LOCALES.values() for locale in locales}
    else:
        locs, _ = asc.get_all(f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")
        by_locale = {loc["attributes"]["locale"]: loc for loc in locs}
    for lang, locales in LOCALES.items():
        video = FOLDER / f"aybuke-app-preview-iphone-{lang}.mp4"
        if not video.exists():
            print(f"skip {lang}: no {video.name}")
            continue
        for locale in locales:
            if ONLY and locale not in ONLY:
                continue
            if locale not in by_locale:
                print(f"skip {locale}: no localization on this version")
                continue
            print(f"{locale}: {video.name} ({video.stat().st_size // 1024} KB)")
            if DRY:
                continue
            set_id = preview_set(by_locale[locale]["id"])
            old, _ = asc.get_all(f"/v1/appPreviewSets/{set_id}/appPreviews")
            for preview in old:
                asc.delete(f"/v1/appPreviews/{preview['id']}")
            upload(set_id, video)
    print("dry run ok" if DRY else "done")


main()
