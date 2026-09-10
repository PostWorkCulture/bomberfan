# Forest lighting evaluation

This is an isolated playable evaluation at `forest-review.html`. The normal
`index.html` and all fighter artwork are unchanged. `forest-preview.html` is a
copy of the game entry with the Forest renderer integrated. Compare Original,
Auto, Balanced and High from the review page; selecting one restarts the same
seeded opening layout. Select Loadout, then Fight to play the Forest map.

## Treatment

- Warm directional sunlight, cool rear fill, subdued woodland hemisphere light.
- One cached 128x64 linear HDR environment, prefiltered with PMREM. No per-frame
  reflection capture and no additional dynamic light slots.
- Tighter shadow coverage, 2048px on High, 1024px on Balanced; tuned bias/radius.
- Bevelled instanced walls and crates inside the existing collision bounds.
- Deterministic woodland floor, restrained normals, wood grain and mossy stone.
- Offline cosine-weighted ambient visibility against the 82 immutable Forest
  wall cells, 64 rays per texel at 384x333. Ground AO plus a small reflected
  colour contribution. No crate, bomb or fighter is present in this bake.
- High: HDR scene target with 2x MSAA; quarter-resolution bright extraction and
  separable blur, then restrained bloom, mild grading and one output transform.
- Auto starts Balanced on touch-first devices. Two consecutive slow sampling
  windows lower High to Balanced; existing adaptive drawing resolution remains.
- Loadout and victory retain their original exposure. Other arena lighting and
  materials are restored when leaving Forest.

## Source and limits

`tools/bake-forest.py` regenerates the textures with Python, NumPy and Pillow.
The bevel geometry is authored in Three.js. These are **not Blender exports**.
Blender was unavailable and installation failed in this environment. There is
no Blender/Cycles render or claim of Blender-to-runtime parity.

Run `node tests/forest-lighting-regression.mjs`, then
`BF_QA_ENTRY=forest-preview.html node tests/platform-regression.mjs`.
The profile suite repeats eight input/viewport profiles twice. It stubs WebGL,
so those results do not measure GPU performance or certify physical devices.

Visual browser verification and device FPS are tracked in the build record.

## Review delivery and verification (10 September 2026)

The public main-branch push was rejected by automatic approval review: the
request authorises an isolated evaluation, not public publication. No production
change was published. A separate draft branch is the source delivery target.

`tools/package-forest-review.py` creates a self-contained downloadable HTML with
all 20 models, 93 embedded assets and nine local modules. No external asset
requests are needed. Download the HTML and open it in a WebGL-capable desktop
browser. Its toolbar switches Original/Auto/Balanced/High; a switch restarts the
same opening seed. Hide the toolbar for an unobstructed view. Choose Loadout,
then Fight. The main game remains unchanged.

Final checks: the Forest-specific resource/geometry suite passed; the eight
platform profiles passed twice on the preview entry (256 check groups), plus
HUD, asset-integrity and HTML/module parsing. The standalone package checks all
20 model dependency sets and module boot order. The initial package test found a
GLTFLoader/SkeletonUtils ordering issue, which was fixed before delivery.

The hosted browser rejected both the local preview URL and the shared file URL.
No alternative browser mechanism was used. Actual WebGL shader execution,
visual appearance, touch behaviour and GPU frame times remain unverified.
The offline HTML is a review build, not a claim that the graphics are approved.
