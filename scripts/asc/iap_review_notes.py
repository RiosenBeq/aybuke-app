"""Sets the App Review notes of both subscriptions and both credit packs: what
each one gives, where the paywall and the packs are in the app (iPhone, iPad
and Mac), and that TestFlight and review purchases run in the sandbox. Keep
the paths in step with ios/App (SettingsView's Membership and Credits
sections, PaywallView's packs link, CreditsSheet's "Get more credits") and
the copy in docs/marketing/app-store-listing.md, which --check compares.

    iap_review_notes.py <repo> [--dry-run | --check]
"""
import sys
from pathlib import Path

GROUP_PRO = (
    "Pro gives 80 AI credits a month (unused credits roll over, up to 160), every look and style, "
    "the best-quality AI, no watermark and no ads."
)
AGE = "Where to find it: in onboarding, choose an age of 13 or older (under 13 the app offers no purchases)."
SETTINGS = (
    "Open Settings (the gear at the top right of Explore; on the Mac, the gear at the bottom of the sidebar, "
    "or Settings… in the app menu)"
)
BALANCE = "after tapping the credit balance (top of Explore; on the Mac, the bottom of the sidebar)"
SANDBOX = (
    "Purchases in TestFlight and in App Review run in the App Store sandbox and aren't charged; our server "
    "verifies Apple's signed transaction and accepts Sandbox transactions."
)
CONSENT = "Using AI credits shows a one-time consent screen first (Supabase, xAI, Anthropic): tap \"Allow AI processing\"."


def pro_note(plan, terms, pick):
    return "\n\n".join([
        f"{plan} (auto-renewable): {terms} {GROUP_PRO}",
        f"{AGE} {SETTINGS} and, under Membership, tap \"Upgrade to Aybuke Pro\" to open the paywall, then pick "
        f"the {pick} plan. The paywall also opens from any look or style marked Pro, from \"Get more credits\" "
        f"{BALANCE}, and when free credits run out. Restore: \"Restore\" on the paywall, or Settings > Membership > "
        "\"Restore purchases\".",
        f"{SANDBOX} {CONSENT}",
    ])


def pack_note(credits, price):
    return "\n\n".join([
        f"{credits} Credits (consumable): {credits} AI credits for {price} that never expire. "
        "1 credit = 1 AI creation or edit.",
        f"{AGE} {SETTINGS} and, under Credits, tap \"Buy a credit pack\". The packs are also below the plans on "
        "the paywall (\"Not ready to subscribe? Get a credit pack\"), and Pro members reach them from "
        f"\"Get more credits\" {BALANCE}.",
        f"{SANDBOX} The credits are added after that check, and the balance updates in the app. {CONSENT}",
    ])


SUBSCRIPTIONS = {
    "6822722945": pro_note("Aybuke Pro Yearly", "$39.99 a year, with a 7-day free trial for eligible new "
                           "subscribers that includes 20 AI credits.", "yearly"),
    "6822727359": pro_note("Aybuke Pro Monthly", "$5.99 a month; eligible new subscribers pay $1.99 for the "
                           "first month.", "monthly"),
}
PACKS = {
    "6822730949": pack_note(30, "$2.99"),
    "6822730794": pack_note(100, "$7.99"),
}


def squash(text):
    return " ".join(text.split())


def main():
    repo = Path(sys.argv[1])
    notes = {**{("subscriptions", k): v for k, v in SUBSCRIPTIONS.items()},
             **{("inAppPurchases", k): v for k, v in PACKS.items()}}
    for note in notes.values():
        assert len(note) <= 4000, len(note)
    listing = squash((repo / "docs/marketing/app-store-listing.md").read_text(encoding="utf-8"))
    missing = [key for key, note in notes.items() if squash(note) not in listing]
    if missing:
        raise SystemExit(f"docs/marketing/app-store-listing.md lacks the review note of {missing}")
    if "--check" in sys.argv:
        print("check ok")
        return

    import asc  # needs requests + cryptography and the API key; the check doesn't

    for (kind, product), note in notes.items():
        path = f"/v1/subscriptions/{product}" if kind == "subscriptions" else f"/v2/inAppPurchases/{product}"
        current = asc.get(path)["data"]["attributes"]
        if current.get("reviewNote") == note:
            print(f"{current.get('productId')}: up to date")
            continue
        print(f"{current.get('productId')}: {'would update' if '--dry-run' in sys.argv else 'updating'} the review note")
        if "--dry-run" not in sys.argv:
            asc.patch(path, {"data": {"type": kind, "id": product, "attributes": {"reviewNote": note}}})
    print("done")


if __name__ == "__main__":
    main()
