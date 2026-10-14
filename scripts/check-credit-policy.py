#!/usr/bin/env python3
"""Fails when the credit numbers drift apart.

The server is authoritative (public.credit_policy() and public.ad_reward_policy()
in the newest migration that defines them), and the app ships the same numbers
as defaults for offline and demo use (AppConfig.json and AppCore). A retune
must change all three, or the app's copy and mirror disagree with the server.

Usage: python3 scripts/check-credit-policy.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "backend/supabase/migrations"
APP_CONFIG = ROOT / "ios/App/Resources/AppConfig.json"
CREDITS_SWIFT = ROOT / "ios/Packages/AppCore/Sources/AppCore/Credits.swift"
ADS_SWIFT = ROOT / "ios/Packages/AppCore/Sources/AppCore/Ads.swift"


def newest_definition(function: str) -> tuple[Path, str]:
    """The body of the newest `create … function public.<function>(` in the migrations."""
    pattern = re.compile(rf"create (?:or replace )?function public\.{function}\(.*?\$\$(.*?)\$\$", re.S | re.I)
    found = None
    for path in sorted(MIGRATIONS.glob("*.sql")):
        for match in pattern.finditer(path.read_text(encoding="utf-8")):
            found = (path, match.group(1))
    if found is None:
        sys.exit(f"no definition of public.{function}() in {MIGRATIONS}")
    return found


def sql_credit_policy() -> tuple[Path, dict[str, int]]:
    path, body = newest_definition("credit_policy")
    values = {name: int(number) for number, name in re.findall(r"(\d+),?\s*--\s*(\w+)", body)}
    return path, values


def sql_ad_reward_cap() -> tuple[Path, int]:
    path, body = newest_definition("ad_reward_policy")
    match = re.search(r"select\s+(\d+)\s*,", body, re.I)
    if not match:
        sys.exit(f"can't read the daily cap from ad_reward_policy() in {path.name}")
    return path, int(match.group(1))


def swift_int(path: Path, label: str) -> int:
    match = re.search(rf"\b{label}:\s*(?:Int\s*=\s*)?(\d+)", path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"can't find {label} in {path.relative_to(ROOT)}")
    return int(match.group(1))


def main() -> int:
    sql_path, sql = sql_credit_policy()
    ad_path, ad_cap = sql_ad_reward_cap()
    config = json.loads(APP_CONFIG.read_text(encoding="utf-8"))
    policy = config["creditPolicy"]

    # (what, server value, [(where, value), ...])
    rows = [
        ("free credits a day", sql.get("free_daily"), [
            ("AppConfig.json creditPolicy.freeDaily", policy.get("freeDaily")),
            ("AppCore CreditPolicy.standard", swift_int(CREDITS_SWIFT, "freeDailyAllowance")),
        ]),
        ("Pro credits a month", sql.get("pro_monthly"), [
            ("AppConfig.json creditPolicy.proMonthly", policy.get("proMonthly")),
            ("AppCore CreditPolicy.standard", swift_int(CREDITS_SWIFT, "proMonthlyAllowance")),
        ]),
        ("Pro rollover cap", sql.get("pro_rollover_cap"), [
            ("AppConfig.json creditPolicy.rolloverCap", policy.get("rolloverCap")),
            ("AppCore CreditPolicy.standard", swift_int(CREDITS_SWIFT, "proRolloverCap")),
        ]),
        ("trial credits", sql.get("trial_credits"), [
            ("AppConfig.json creditPolicy.trialCredits", policy.get("trialCredits")),
            ("AppCore CreditPolicy.standard", swift_int(CREDITS_SWIFT, "trialCredits")),
        ]),
        ("Likeness Lock retries a day", sql.get("free_retries_daily"), [
            ("AppConfig.json creditPolicy.freeRetriesDaily", policy.get("freeRetriesDaily")),
            ("AppCore CreditPolicy.standard", swift_int(CREDITS_SWIFT, "freeRetriesPerDay")),
        ]),
        ("rewarded ads a day", ad_cap, [
            ("AppConfig.json ads.dailyCap", config.get("ads", {}).get("dailyCap")),
            ("AppCore AdRewardPolicy default", swift_int(ADS_SWIFT, "dailyCap")),
        ]),
    ]

    problems = []
    for what, server, copies in rows:
        if server is None:
            problems.append(f"{what}: missing from {sql_path.name}")
            continue
        for where, value in copies:
            if value != server:
                problems.append(f"{what}: server says {server}, {where} says {value}")

    if problems:
        print(f"Credit numbers drift (server: {sql_path.name}, {ad_path.name}):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(f"Credit numbers agree ({sql_path.name}, {ad_path.name}, AppConfig.json, AppCore).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
