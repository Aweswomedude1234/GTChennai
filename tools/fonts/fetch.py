#!/usr/bin/env python3
"""Download the OFL font families used for signage and UI as full TTFs from the google/fonts
repo into godot/fonts/. Godot shapes Tamil and other Indic scripts with HarfBuzz, so full
fonts (not unicode-range web subsets) are required. Run from the repo root."""
import os, re, urllib.request

FAMILIES = ["baloothambi2", "arima", "catamaran", "notosanstamil", "kavivanar", "hindmadurai",
            "anton", "oswald", "notosans", "notoserif", "notosanstelugu", "notosansdevanagari",
            "notosansmalayalam", "notosanskannada", "muktamalar", "meerainimai"]
RAW = "https://raw.githubusercontent.com/google/fonts/main/ofl/"
OUT = "godot/fonts"
os.makedirs(OUT, exist_ok=True)
for fam in FAMILIES:
    meta = urllib.request.urlopen(RAW + fam + "/METADATA.pb").read().decode()
    files = re.findall(r'filename: "([^"]+)"', meta)
    # variable fonts carry every weight; for static families keep regular..extrabold only
    if not any("[" in f for f in files):
        keep = [f for f in files if re.search(r"-(Regular|Medium|SemiBold|Bold|ExtraBold)\.ttf$", f)] or files[:1]
    else:
        keep = [f for f in files if "Italic" not in f]
    for f in keep:
        dst = os.path.join(OUT, f.replace("[", "_").replace("]", "").replace(",", "_"))
        if not os.path.exists(dst):
            urllib.request.urlretrieve(RAW + fam + "/" + urllib.request.quote(f), dst)
    lic = os.path.join(OUT, "OFL_" + fam + ".txt")
    if not os.path.exists(lic):
        urllib.request.urlretrieve(RAW + fam + "/OFL.txt", lic)
    print(fam, keep)
