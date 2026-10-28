#!/usr/bin/env python3
"""License gate for patches/series.yaml: any GPL entry fails the build.

The repo ships MIT only; GPL-3.0 sources (e.g. Droid-Deck/Drivers) must never
be collected. Run locally or from CI; exit 0 means clean.
"""
import re
import sys

text = open('patches/series.yaml').read()
bad = []
for m in re.finditer(r'^  - file: (.+)\n((?:    .*\n?)+)', text, re.M):
    lic = re.search(r'^    license: (.+)$', m.group(2), re.M)
    if lic and 'GPL' in lic.group(1).upper():
        bad.append((m.group(1), lic.group(1)))
if bad:
    for f, l in bad:
        print(f'GPL entry: {f} ({l})')
    sys.exit(1)
count = len(re.findall(r'^  - file: ', text, re.M))
print(f'license gate ok: {count} patches, no GPL entries')
