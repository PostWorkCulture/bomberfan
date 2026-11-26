#!/bin/bash
# A/B check for your fighter's x-ray silhouette: renders the same seeded match
# with and without the pass and writes side-by-side frames plus diff masks.
# Visible parts of your fighter must match; differences belong only where
# something stands in front of you.
#   GODOT=~/godot-bin/godot tools/xray_ab.sh <outdir> [arena] [seed]
out=${1:-/tmp/xray-ab}; lv=${2:-beach}; sd=${3:-5}
cd "$(dirname "$0")/.."
rm -rf "$out"; mkdir -p "$out/on" "$out/off"
for mode in on off; do
  extra=""; [ $mode = off ] && extra="--no-xray"
  xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path godot --rendering-driver opengl3 --resolution 1280x720 \
    --fixed-fps 10 --write-movie "$out/$mode/t.png" --quit-after 140 -- --demo --autopilot --level "$lv" --seed "$sd" $extra > "$out/$mode/log.txt" 2>&1
done
python3 - "$out" <<'PY'
import sys
import numpy as np
from PIL import Image
out = sys.argv[1]
for n in (60, 80, 100, 120, 138):
    a = Image.open(f"{out}/on/t{n:08d}.png").convert("RGB")
    b = Image.open(f"{out}/off/t{n:08d}.png").convert("RGB")
    d = (np.abs(np.asarray(a, int) - np.asarray(b, int)).sum(2) > 30)
    g = Image.new("RGB", (a.width * 3, a.height))
    g.paste(a, (0, 0)); g.paste(b, (a.width, 0)); g.paste(Image.fromarray((d * 255).astype("uint8")).convert("RGB"), (a.width * 2, 0))
    g.save(f"{out}/ab_{n}.png")
    print(n, "differing pixels:", int(d.sum()))
PY
