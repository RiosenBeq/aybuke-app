"""Gives the subscription group, both subscriptions and both credit packs a name
and description in all 13 App Store locales (renamed to Aybuke)."""
import asc

LOCALES = ["en-US", "tr", "es-ES", "es-MX", "pt-BR", "fr-FR", "de-DE", "it", "ru", "ja", "ko", "zh-Hans", "id"]

PRO_DESC = {
    "en-US": "80 credits a month, every look, best AI",
    "tr": "Ayda 80 kredi, tüm görünümler, en iyi AI",
    "es-ES": "80 créditos/mes, todos los looks, mejor IA",
    "es-MX": "80 créditos/mes, todos los looks, mejor IA",
    "pt-BR": "80 créditos/mês, todos os looks, melhor IA",
    "fr-FR": "80 crédits par mois et tous les looks",
    "de-DE": "80 Credits im Monat, alle Looks, beste KI",
    "it": "80 crediti al mese e tutti i look",
    "ru": "80 кредитов в месяц и все образы",
    "ja": "毎月80クレジット、すべてのルック",
    "ko": "매월 80 크레딧, 모든 룩",
    "zh-Hans": "每月 80 点数，所有造型",
    "id": "80 kredit sebulan, semua gaya, AI terbaik",
}
YEARLY = {
    "en-US": "Aybuke Pro Yearly", "tr": "Aybuke Pro Yıllık", "es-ES": "Aybuke Pro Anual", "es-MX": "Aybuke Pro Anual",
    "pt-BR": "Aybuke Pro Anual", "fr-FR": "Aybuke Pro Annuel", "de-DE": "Aybuke Pro Jährlich", "it": "Aybuke Pro Annuale",
    "ru": "Aybuke Pro на год", "ja": "Aybuke Pro 年間", "ko": "Aybuke Pro 연간", "zh-Hans": "Aybuke Pro 年度", "id": "Aybuke Pro Tahunan",
}
MONTHLY = {
    "en-US": "Aybuke Pro Monthly", "tr": "Aybuke Pro Aylık", "es-ES": "Aybuke Pro Mensual", "es-MX": "Aybuke Pro Mensual",
    "pt-BR": "Aybuke Pro Mensal", "fr-FR": "Aybuke Pro Mensuel", "de-DE": "Aybuke Pro Monatlich", "it": "Aybuke Pro Mensile",
    "ru": "Aybuke Pro на месяц", "ja": "Aybuke Pro 月間", "ko": "Aybuke Pro 월간", "zh-Hans": "Aybuke Pro 月度", "id": "Aybuke Pro Bulanan",
}
CREDITS_NAME = {
    "en-US": "{n} Credits", "tr": "{n} Kredi", "es-ES": "{n} créditos", "es-MX": "{n} créditos", "pt-BR": "{n} créditos",
    "fr-FR": "{n} crédits", "de-DE": "{n} Credits", "it": "{n} crediti", "ru": "{n} кредитов", "ja": "{n}クレジット",
    "ko": "{n} 크레딧", "zh-Hans": "{n} 点数", "id": "{n} Kredit",
}
CREDITS_DESC = {
    "en-US": "{n} AI credits that never expire", "tr": "Süresi dolmayan {n} yapay zekâ kredisi",
    "es-ES": "{n} créditos de IA que no caducan", "es-MX": "{n} créditos de IA que no vencen",
    "pt-BR": "{n} créditos de IA que não expiram", "fr-FR": "{n} crédits IA qui n'expirent jamais",
    "de-DE": "{n} KI-Credits, die nie verfallen", "it": "{n} crediti IA che non scadono mai",
    "ru": "{n} кредитов ИИ без срока действия", "ja": "期限のない{n} AIクレジット",
    "ko": "만료되지 않는 AI 크레딧 {n}개", "zh-Hans": "{n} 个永不过期的 AI 点数", "id": "{n} kredit AI yang tidak kedaluwarsa",
}

GROUP_ID = "22475412"
SUBSCRIPTIONS = {"6822722945": YEARLY, "6822727359": MONTHLY}
PACKS = {"6822730949": 30, "6822730794": 100}


def check(name, desc):
    assert len(name) <= 30, (name, len(name))
    assert len(desc) <= 45, (desc, len(desc))


def sync(existing, create, update, wanted):
    by_locale = {item["attributes"]["locale"]: item for item in existing}
    for locale in LOCALES:
        attrs = wanted(locale)
        item = by_locale.get(locale)
        if item:
            current = {k: item["attributes"].get(k) for k in attrs}
            if current != attrs:
                update(item["id"], attrs)
                print("  updated", locale, attrs)
        else:
            create(locale, attrs)
            print("  created", locale, attrs)


def main():
    print("group")
    existing, _ = asc.get_all(f"/v1/subscriptionGroups/{GROUP_ID}/subscriptionGroupLocalizations")
    sync(existing,
         lambda locale, attrs: asc.post("/v1/subscriptionGroupLocalizations", {"data": {
             "type": "subscriptionGroupLocalizations", "attributes": {"locale": locale, **attrs},
             "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": GROUP_ID}}}}}),
         lambda id_, attrs: asc.patch(f"/v1/subscriptionGroupLocalizations/{id_}", {"data": {
             "type": "subscriptionGroupLocalizations", "id": id_, "attributes": attrs}}),
         lambda locale: {"name": "Aybuke Pro"})
    for sub_id, names in SUBSCRIPTIONS.items():
        print("subscription", sub_id)
        for locale in LOCALES:
            check(names[locale], PRO_DESC[locale])
        existing, _ = asc.get_all(f"/v1/subscriptions/{sub_id}/subscriptionLocalizations")
        sync(existing,
             lambda locale, attrs, sub_id=sub_id: asc.post("/v1/subscriptionLocalizations", {"data": {
                 "type": "subscriptionLocalizations", "attributes": {"locale": locale, **attrs},
                 "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub_id}}}}}),
             lambda id_, attrs: asc.patch(f"/v1/subscriptionLocalizations/{id_}", {"data": {
                 "type": "subscriptionLocalizations", "id": id_, "attributes": attrs}}),
             lambda locale, names=names: {"name": names[locale], "description": PRO_DESC[locale]})
    for iap_id, n in PACKS.items():
        print("credit pack", iap_id)
        for locale in LOCALES:
            check(CREDITS_NAME[locale].format(n=n), CREDITS_DESC[locale].format(n=n))
        existing, _ = asc.get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
        sync(existing,
             lambda locale, attrs, iap_id=iap_id: asc.post("/v1/inAppPurchaseLocalizations", {"data": {
                 "type": "inAppPurchaseLocalizations", "attributes": {"locale": locale, **attrs},
                 "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}),
             lambda id_, attrs: asc.patch(f"/v1/inAppPurchaseLocalizations/{id_}", {"data": {
                 "type": "inAppPurchaseLocalizations", "id": id_, "attributes": attrs}}),
             lambda locale, n=n: {"name": CREDITS_NAME[locale].format(n=n), "description": CREDITS_DESC[locale].format(n=n)})


main()
