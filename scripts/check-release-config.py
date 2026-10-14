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
PLACEHOLDER = re.compile(r"^\s*\[.*\]\s*$", re.DOTALL)


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
        for url in (website, website + "/legal/en/privacy-policy.html"):
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
    app_config = check_app_config(findings)
    legal_config = check_legal(findings)
    if online:
        check_online(app_config, legal_config, findings)

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
