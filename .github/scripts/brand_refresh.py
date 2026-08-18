from PIL import Image
from pathlib import Path
import json
import re

logo_path = Path('Main Logo.png')
if not logo_path.exists():
    raise SystemExit('Main Logo.png not found')

img = Image.open(logo_path).convert('RGBA')
w, h = img.size
side = min(w, h)
img = img.crop(((w-side)//2, (h-side)//2, (w+side)//2, (h+side)//2))

for size, name in [(192, 'icon-192.png'), (512, 'icon-512.png'), (180, 'apple-touch-icon.png')]:
    img.resize((size, size), Image.Resampling.LANCZOS).save(name, optimize=True)

mask = Image.new('RGBA', (512, 512), (9, 10, 14, 255))
inner = img.resize((410, 410), Image.Resampling.LANCZOS)
mask.alpha_composite(inner, ((512-410)//2, (512-410)//2))
mask.save('icon-maskable.png', optimize=True)

manifest = {
    'name': 'Bomber Fan',
    'short_name': 'Bomber Fan',
    'description': 'A 3D local-multiplayer bomber game.',
    'start_url': './',
    'scope': './',
    'display': 'fullscreen',
    'background_color': '#090a0d',
    'theme_color': '#f28a18',
    'icons': [
        {'src': 'icon-192.png', 'sizes': '192x192', 'type': 'image/png', 'purpose': 'any'},
        {'src': 'icon-512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'any'},
        {'src': 'icon-maskable.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'maskable'}
    ]
}
Path('manifest.webmanifest').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')

p = Path('index.html')
s = p.read_text(encoding='utf-8')

# Replace whichever icon links are currently in the page.
s = re.sub(r'<link rel="icon"[^>]*>', '<link rel="icon" type="image/png" href="icon-192.png">', s, count=1)
s = re.sub(r'<link rel="apple-touch-icon"[^>]*>', '<link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">', s, count=1)

marker = '/* BOMBER FAN MAIN LOGO BRAND REFRESH V2 */'
if marker not in s:
    css = r'''
  /* BOMBER FAN MAIN LOGO BRAND REFRESH V2 */
  #menu {
    isolation: isolate;
    justify-content: center !important;
    background:
      radial-gradient(circle at 50% 18%, rgba(255,163,54,.34) 0%, rgba(255,95,18,.14) 23%, transparent 44%),
      linear-gradient(180deg, rgba(7,8,11,.22), rgba(3,4,6,.93)),
      radial-gradient(ellipse at center, #17191f 0%, #090a0e 55%, #030406 100%) !important;
    overflow: hidden;
  }
  #menu::before {
    content: ''; position: absolute; inset: -8%; z-index: -2; pointer-events: none;
    background:
      radial-gradient(2px 2px at 12% 18%, rgba(255,188,80,.92), transparent),
      radial-gradient(1.5px 1.5px at 29% 73%, rgba(255,101,24,.78), transparent),
      radial-gradient(2px 2px at 73% 23%, rgba(255,219,142,.75), transparent),
      radial-gradient(1.4px 1.4px at 86% 66%, rgba(255,126,30,.72), transparent),
      linear-gradient(112deg, transparent 0 48%, rgba(255,130,28,.06) 49% 50%, transparent 51% 100%);
    background-size: 121px 121px, 167px 167px, 211px 211px, 149px 149px, auto;
    opacity: .52;
    animation: bfEmbers 9s linear infinite alternate;
  }
  #menu::after {
    content: ''; position: absolute; inset: 0; z-index: -1; pointer-events: none;
    background:
      linear-gradient(90deg, transparent 0 8%, rgba(255,255,255,.018) 8.2% 8.4%, transparent 8.6% 91%, rgba(255,255,255,.018) 91.2% 91.4%, transparent 91.6%),
      linear-gradient(180deg, rgba(255,124,20,.035), transparent 18%, transparent 78%, rgba(0,0,0,.42));
    box-shadow: inset 0 0 150px rgba(0,0,0,.82), inset 0 -100px 120px rgba(0,0,0,.54);
  }
  @keyframes bfEmbers { from { transform: translateY(0); } to { transform: translateY(-13px); } }

  #menu h1 {
    width: min(34vw, 39vh, 350px) !important;
    height: auto !important;
    aspect-ratio: 1 !important;
    flex: 0 0 auto !important;
    margin: -1vh 0 4px !important;
    padding: 0 !important;
    background: url('Main Logo.png') center / contain no-repeat !important;
    font-size: 0 !important;
    line-height: 0 !important;
    letter-spacing: 0 !important;
    filter: drop-shadow(0 15px 18px rgba(0,0,0,.76)) drop-shadow(0 0 40px rgba(255,125,19,.40));
    animation: bfLogoFloat 3.1s ease-in-out infinite alternate;
  }
  #menu h1 > * { opacity: 0 !important; visibility: hidden !important; pointer-events: none !important; }
  @keyframes bfLogoFloat {
    from { transform: translateY(0) scale(1); }
    to { transform: translateY(-5px) scale(1.018); }
  }

  #menu .opts {
    width: min(530px, 88vw) !important;
    margin-top: 0 !important;
    gap: 8px !important;
    padding: 12px !important;
    border-radius: 22px !important;
    background:
      linear-gradient(180deg, rgba(27,29,34,.78), rgba(8,9,12,.86)) !important;
    border: 1px solid rgba(255,159,48,.18) !important;
    box-shadow:
      0 24px 60px rgba(0,0,0,.54),
      inset 0 1px 0 rgba(255,255,255,.05),
      0 0 38px rgba(255,112,13,.07) !important;
    backdrop-filter: blur(14px) saturate(1.16) !important;
  }
  #menu .opt {
    min-height: 50px !important;
    padding: 12px 18px !important;
    border-radius: 13px !important;
    position: relative !important;
    overflow: hidden !important;
    background:
      linear-gradient(180deg, rgba(41,43,49,.97), rgba(14,15,19,.99)) !important;
    border: 1px solid rgba(255,153,43,.26) !important;
    box-shadow:
      inset 0 1px 0 rgba(255,255,255,.065),
      inset 4px 0 0 rgba(255,134,28,.12),
      0 6px 18px rgba(0,0,0,.36) !important;
    transition: transform .12s ease, border-color .12s ease, box-shadow .12s ease, background .12s ease !important;
  }
  #menu .opt::before {
    content: ''; position: absolute; inset: 0; pointer-events: none;
    background: linear-gradient(105deg, transparent 0 50%, rgba(255,190,92,.10) 67%, transparent 84%);
    transform: translateX(-48%);
    transition: transform .26s ease;
  }
  #menu .opt::after {
    content: ''; position: absolute; left: 0; top: 10px; bottom: 10px; width: 3px;
    border-radius: 0 3px 3px 0;
    background: linear-gradient(#ffc86b, #f06c12);
    opacity: .24;
    box-shadow: 0 0 14px rgba(255,113,19,.36);
    transition: opacity .12s ease;
  }
  #menu .opt:hover::before, #menu .opt.sel::before { transform: translateX(24%); }
  #menu .opt:hover::after, #menu .opt.sel::after { opacity: 1; }
  #menu .opt:hover, #menu .opt.sel, #menu .opt:focus-within {
    transform: translateY(-2px) scale(1.008) !important;
    border-color: rgba(255,176,74,.92) !important;
    background: linear-gradient(180deg, rgba(76,45,23,.99), rgba(27,18,12,.99)) !important;
    box-shadow:
      inset 0 1px 0 rgba(255,231,187,.14),
      inset 4px 0 0 rgba(255,145,33,.66),
      0 0 0 1px rgba(255,118,15,.14),
      0 0 26px rgba(255,111,13,.23),
      0 12px 30px rgba(0,0,0,.50) !important;
  }
  #menu .opt:active { transform: translateY(1px) scale(.996) !important; }
  #menu .opt .lbl {
    color: rgba(255,255,255,.94) !important;
    font-weight: 850 !important;
    letter-spacing: .45px !important;
    text-shadow: 0 1px 0 rgba(0,0,0,.70) !important;
  }
  #menu .opt .lbl.start {
    color: #ffe5b1 !important;
    font-weight: 950 !important;
    letter-spacing: 1.45px !important;
    text-transform: uppercase !important;
    text-shadow: 0 1px 0 #000, 0 0 18px rgba(255,139,32,.48) !important;
  }
  #menu .opt .val {
    color: #ffb54f !important;
    font-weight: 900 !important;
    letter-spacing: .55px !important;
    text-shadow: 0 0 12px rgba(255,131,31,.24) !important;
  }
  #menu .build { color: #ffb04b !important; opacity: .38 !important; }

  @media (prefers-reduced-motion: reduce) {
    #menu h1, #menu::before { animation: none !important; }
    #menu .opt, #menu .opt::before { transition: none !important; }
  }
  @media (max-height: 560px) {
    #menu h1 { width: min(24vw, 31vh, 174px) !important; margin: -1vh 0 1px !important; }
    #menu .opts { width: min(500px, 80vw) !important; gap: 4px !important; padding: 6px !important; border-radius: 15px !important; }
    #menu .opt { min-height: 34px !important; padding: 6px 12px !important; border-radius: 9px !important; }
  }
  @media (max-height: 420px) {
    #menu h1 { width: min(19vw, 25vh, 116px) !important; }
    #menu .opts { gap: 3px !important; padding: 4px !important; }
    #menu .opt { min-height: 29px !important; padding: 4px 10px !important; }
  }
'''
    s = s.replace('</style>', css + '\n</style>', 1)

p.write_text(s, encoding='utf-8')
print('Bomber Fan front branding patched.')
