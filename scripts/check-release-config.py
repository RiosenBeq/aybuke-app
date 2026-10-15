#!/usr/bin/env python3
"""Stops demo-mode or placeholder builds from reaching App Review (Guideline 2.1).

Checks what actually ships:
- AppConfig.json decodes and selects the backend exactly as AppConfig.backend
  does (https backendBaseURL, a Supabase anon key, forceDemoMode false).
  Otherwise the build runs in demo mode: stamped sample results, no accounts,
  while the App Store still sells real Pro and packs.
- No [bracketed] placeholder is left in legal/config.json (company name,
  address, representatives…), and the bundled legal copies are current.
- websiteURL (share captions and the invite QR code) is an https URL and not
  a GitHub blob page.
- Ads: when AppConfig.json turns them on, the AdMob app id in Release.xcconfig
  (Info.plist's GADApplicationIdentifier) is Glowlit's, not Google's sample,
  and matches ads.appID and the units' publisher; otherwise the app quietly
  shows no ads. An empty interstitial unit is reported as a note only.
With --online, also: the website and its privacy policy answer 200, and the
support and legal email domains can receive mail (MX records).

  python3 scripts/check-release-config.py            # offline, exits 1 on findings
  python3 scripts/check-release-config.py --online   # what upload-app-store.sh runs
  python3 scripts/check-release-config.py --report   # print findings, exit 0 (CI)

GL_PREVIEW_BUILD=1 turns findings into warnings for a deliberate preview
upload (TestFlight before Supabase and the company details exist). Such a
build must never be submitted for review.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
APP_CONFIG = ROOT / "ios/App/Resources/AppConfig.json"
LEGAL_CONFIG = ROOT / "legal/config.json"
RELEASE_XCCONFIG = ROOT / "ios/Config/Release.xcconfig"
PLACEHOLDER = re.compile(r"^\s*\[.*\]\s*$", re.DOTALL)
ADMOB_APP_ID = re.compile(r"^ca-app-pub-(\d{10,20})~\d{6,14}$")
ADMOB_UNIT_ID = re.compile(r"^ca-app-pub-(\d{10,20})/\d{6,14}$")
GOOGLE_SAMPLE_PUBLISHER = "3940256099942544"


def check_ads(config, findings, notes):
    """The same rules AdsConfig applies at runtime (a mismatch turns ads off)."""
    ads = config.get("ads") or {}
    if not ads.get("enabled"):
        notes.append("Ads are off (ads.enabled is false in AppConfig.json).")
        return
    app_id = (ads.get("appID") or "").strip()
    match = ADMOB_APP_ID.match(app_id)
    if not match or match.group(1) == GOOGLE_SAMPLE_PUBLISHER:
        findings.append("ads.appID in AppConfig.json isn't Glowlit's AdMob app id; release builds would show no ads.")
        return
    publisher = match.group(1)
    settings = {}
    for line in RELEASE_XCCONFIG.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("//"):
            key, value = line.split("=", 1)
            settings[key.strip()] = value.split("//", 1)[0].strip()
    if settings.get("GL_ADMOB_APP_ID") != app_id:
        findings.append("GL_ADMOB_APP_ID in Release.xcconfig doesn't match ads.appID; release builds would show no ads.")
    rewarded = ADMOB_UNIT_ID.match((ads.get("rewardedUnitID") or "").strip())
    if not rewarded or rewarded.group(1) != publisher:
        findings.append("ads.rewardedUnitID isn't one of this AdMob account's units; rewarded ads would stay off.")
    interstitial = (ads.get("interstitialUnitID") or "").strip()
    if not interstitial:
        notes.append("ads.interstitialUnitID is empty: no interstitials until it's set.")
    elif not ADMOB_UNIT_ID.match(interstitial) or ADMOB_UNIT_ID.match(interstitial).group(1) != publisher:
        findings.append("ads.interstitialUnitID isn't one of this AdMob account's units; interstitials would stay off.")


def check_app_config(findings):
    try:
        config = json.loads(APP_CONFIG.read_text(encoding="utf-8"))
        assert isinstance(config, dict)
    except (OSError, ValueError, AssertionError) as error:
        # The app would silently fall back to AppConfig.fallback (demo mode).
        findings.append(f"AppConfig.json doesn't decode ({error}); the app would run in demo mode.")
        return {}

    base = (config.get("backendBaseURL") or "").strip()
    reasons = []
    if config.get("forceDemoMode"):
        reasons.append("forceDemoMode is true")
    if urlparse(base).scheme != "https" or not urlparse(base).netloc:
        reasons.append("backendBaseURL is not an https URL")
    if not (config.get("supabaseAnonKey") or "").strip():
        reasons.append("supabaseAnonKey is empty")
    if reasons:
        findings.append("Demo mode: " + ", ".join(reasons) + ". See docs/SUPABASE-TODO.md.")

    website = (config.get("websiteURL") or "").strip()
    parsed = urlparse(website)
    if parsed.scheme != "https" or not parsed.netloc:
        findings.append("websiteURL must be an https URL (it feeds share captions and the invite QR code).")
    elif parsed.netloc.endswith("github.com") and "/blob/" in parsed.path:
        findings.append("websiteURL points to a GitHub blob page; use the published site.")
    return config


def check_legal(findings):
    try:
        config = json.loads(LEGAL_CONFIG.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        findings.append(f"legal/config.json doesn't decode ({error}).")
        return {}
    for section in ("shared", "en", "tr"):
        for key, value in (config.get(section) or {}).items():
            if isinstance(value, str) and PLACEHOLDER.match(value):
                findings.append(f"legal/config.json {section}.{key} is still a placeholder: {value}")
    stale = subprocess.run(
        [sys.executable, str(ROOT / "scripts/build-legal.py"), "--check"],
        capture_output=True, text=True,
    )
    if stale.returncode != 0:
        findings.append("Legal documents are out of date: run python3 scripts/build-legal.py.")
    return config


def http_ok(url):
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "glowlit-release-check"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status == 200
    except (urllib.error.URLError, OSError):
        return False


def has_mx(domain):
    if shutil.which("dig"):
        result = subprocess.run(["dig", "+short", "MX", domain], capture_output=True, text=True, timeout=20)
        return bool(result.stdout.strip())
    if shutil.which("nslookup"):
        result = subprocess.run(["nslookup", "-type=mx", domain], capture_output=True, text=True, timeout=20)
        return "mail exchanger" in result.stdout
    return True  # can't tell; don't block


def check_online(app_config, legal_config, findings):
    website = (app_config.get("websiteURL") or "").strip().rstrip("/")
    if website.startswith("https://"):
        # The URLs the app opens, so a redirect (Vercel's clean URLs answer
        # 308, which urllib before Python 3.11 doesn't follow) can't fail it.
        legal = [(app_config.get(key) or "").strip() for key in ("privacyPolicyURL", "termsURL")]
        for url in [website] + [u for u in legal if u.startswith("https://")]:
            if not http_ok(url):
                findings.append(f"{url} doesn't answer 200.")
    emails = {app_config.get("supportEmail", "")}
    emails |= {(legal_config.get("shared") or {}).get(key, "") for key in ("CONTACT_EMAIL", "PRIVACY_EMAIL")}
    for email in sorted(e for e in emails if "@" in e):
        domain = email.rsplit("@", 1)[1]
        if not has_mx(domain):
            findings.append(f"{email} can't receive mail: {domain} has no MX record.")


def main(argv):
    online = "--online" in argv
    report_only = "--report" in argv
    preview = os.environ.get("GL_PREVIEW_BUILD") == "1"

    findings = []
    notes = []
    app_config = check_app_config(findings)
    if app_config:
        check_ads(app_config, findings, notes)
    legal_config = check_legal(findings)
    if online:
        check_online(app_config, legal_config, findings)

    for note in notes:
        print(f"note: {note}")
    if not findings:
        print("Release config check passed.")
        return 0
    label = "warning" if (preview or report_only) else "error"
    for finding in findings:
        print(f"{label}: {finding}")
    if preview:
        print("GL_PREVIEW_BUILD=1: preview build. Do not submit this build for review.")
        return 0
    if report_only:
        return 0
    print(f"\n{len(findings)} release blocker(s). For a deliberate preview upload set GL_PREVIEW_BUILD=1.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
