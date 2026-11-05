#!/usr/bin/env python3
"""A Play bolti szövegek karakter-korlátainak ellenőrzése.

A Play kemény korlátai: név <= 30 karakter, rövid leírás <= 80, teljes <= 4000,
kiadási megjegyzés <= 500. Ezt MÉRNI kell, nem érezni.

FORRÁS: `fastlane/metadata/android/<nyelv>/` — ez a Play szabványos formátuma,
és ezt tölti fel az ember (vagy egy automata). Korábban ez az ellenőrző a
`store/listing.md`-t mérte, ami a szövegek MÁSODIK példánya volt: a kettő
elcsúszhatott egymástól, és az ellenőrző a nem-feltöltendő változatot hitelesítette.
A listing.md mostantól ebből a forrásból generált, ember által olvasható másolat.
"""
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
META = os.path.join(ROOT, "fastlane", "metadata", "android")

FIELDS = [("title.txt", 30), ("short_description.txt", 80), ("full_description.txt", 4000)]

# Kiadási megjegyzés („Újdonságok”) verziókódonként: changelogs/<versionCode>.txt
CHANGELOG_LIMIT = 500

fails = 0
print(f"{'nyelv / mező':46}{'mért':>8}{'max':>8}  eredmény")
print("-" * 76)
langs = sorted(d for d in os.listdir(META) if os.path.isdir(os.path.join(META, d)))
if not langs:
    sys.exit("nincs egyetlen nyelvi mappa sem a fastlane/metadata/android alatt")

for lang in langs:
    for fname, limit in FIELDS:
        path = os.path.join(META, lang, fname)
        if not os.path.exists(path):
            print(f"{lang + '/' + fname:46}{'-':>8}{limit:>8}  HIÁNYZIK")
            fails += 1
            continue
        text = open(path, encoding="utf-8").read().strip()
        n = len(text)
        ok = 0 < n <= limit
        if not ok:
            fails += 1
        print(f"{lang + '/' + fname:46}{n:>8}{limit:>8}  {'OK' if ok else 'KORLÁT-SÉRTÉS'}")

# A kiadási megjegyzések nyelvenként több fájl is lehetnek (verziónként egy),
# ezért külön körben mérjük. Hiányuk NEM hiba: új kiadás előtt születnek meg.
for lang in langs:
    cdir = os.path.join(META, lang, "changelogs")
    if not os.path.isdir(cdir):
        continue
    for fname in sorted(os.listdir(cdir)):
        if not fname.endswith(".txt"):
            continue
        text = open(os.path.join(cdir, fname), encoding="utf-8").read().strip()
        n = len(text)
        ok = 0 < n <= CHANGELOG_LIMIT
        if not ok:
            fails += 1
        label = f"{lang}/changelogs/{fname}"
        print(f"{label:46}{n:>8}{CHANGELOG_LIMIT:>8}  {'OK' if ok else 'KORLÁT-SÉRTÉS'}")

print("-" * 76)
print(f"nyelvek: {', '.join(langs)}")
print(f"ÖSSZESEN: {fails} hiba")
sys.exit(1 if fails else 0)
