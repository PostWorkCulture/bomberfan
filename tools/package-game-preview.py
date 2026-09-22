"""Package the entire Bomber Fan game into a standalone offline HTML artifact.
No localhost servers or external network requests required.
"""
from pathlib import Path
import json, base64, re

root = Path(__file__).resolve().parents[1]
artifacts_dir = Path(r"C:\Users\peteb\.gemini\antigravity\brain\8e2279d2-b189-4de5-9690-68f3f4653b83")
artifacts_dir.mkdir(parents=True, exist_ok=True)

mimes = {
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.bin': 'application/octet-stream',
    '.gltf': 'model/gltf+json'
}

# 1. Collect all assets
assets = {}

# Characters (glTF, bin, png)
char_dir = root / 'assets/characters'
for path in char_dir.iterdir():
    if path.name.endswith(('.backup.png', '.backup.webp')):
        continue
    if path.suffix in mimes:
        key = path.relative_to(root).as_posix()
        assets[key] = [mimes[path.suffix], base64.b64encode(path.read_bytes()).decode()]

# Portraits
port_dir = root / 'assets/portraits'
for path in port_dir.iterdir():
    if path.name.endswith(('.backup.png', '.backup.webp')):
        continue
    if path.suffix in mimes:
        key = path.relative_to(root).as_posix()
        assets[key] = [mimes[path.suffix], base64.b64encode(path.read_bytes()).decode()]

# Forest & Lighting textures
for dname in ['assets/forest', 'assets/lighting']:
    pdir = root / dname
    if pdir.exists():
        for path in pdir.iterdir():
            if path.suffix in mimes:
                key = path.relative_to(root).as_posix()
                assets[key] = [mimes[path.suffix], base64.b64encode(path.read_bytes()).decode()]

# Root images
for fname in ['Main Logo.png', 'icon-192.png', 'apple-touch-icon.png']:
    p = root / fname
    if p.exists() and p.suffix in mimes:
        assets[fname] = [mimes[p.suffix], base64.b64encode(p.read_bytes()).decode()]

print(f"Collected {len(assets)} offline assets.")

# 2. Collect vendor modules
modules = {}
vendor_files = [
    'three.core.min.js',
    'three.module.min.js',
    'BufferGeometryUtils.js',
    'SkeletonUtils.js',
    'GLTFLoader.js',
    'roster-eyes.js',
    'arena-lighting.js',
    'pirate-water.js',
    'character-bootstrap.js'
]

for name in vendor_files:
    text = (root / 'assets/vendor' / name).read_text(encoding='utf-8')
    # Point internal asset URLs to BFOfflineAssets
    if name == 'roster-eyes.js':
        text = text.replace(
            "new URL('../characters/roster-eye-atlas.png',import.meta.url).href",
            "window.BFOfflineAssets['assets/characters/roster-eye-atlas.png']"
        ).replace(
            "new URL('../characters/roster-eye-atlas.png', import.meta.url).href",
            "window.BFOfflineAssets['assets/characters/roster-eye-atlas.png']"
        )
    elif name == 'arena-lighting.js':
        text = text.replace(
            "new URL(`../${files.includes(name) ? 'forest' : 'lighting'}/${name}.png`, import.meta.url).href",
            "window.BFOfflineAssets['assets/' + (files.includes(name) ? 'forest' : 'lighting') + '/' + name + '.png']"
        )
    modules[name] = text

# 3. Process index.html
html = (root / 'index.html').read_text(encoding='utf-8')

# Extract main module script
scripts = re.findall(r'<script type="module">(.*?)</script>', html, re.DOTALL)
if not scripts:
    raise ValueError("Could not find <script type=\"module\"> in index.html")
main = scripts[0]

# Fix asset loading in main script
main = main.replace(
    'loader.loadAsync(def.model)',
    'loader.loadAsync(window.BFOfflineAssets[def.model] || def.model)'
)
main = main.replace(
    '${def.portrait}?v=${BUILD_ID}',
    '${window.BFOfflineAssets[def.portrait] || def.portrait}'
)
main = main.replace(
    "def.portrait + '?v=' + BUILD_ID",
    "window.BFOfflineAssets[def.portrait] || def.portrait"
)
main = main.replace("'./assets/vendor/three.module.min.js'", "'./three.module.min.js'")
main = main.replace("'./assets/vendor/arena-lighting.js'", "'./arena-lighting.js'")
main = main.replace("'./assets/vendor/pirate-water.js'", "'./pirate-water.js'")

# Execute immediately on module import rather than waiting for window load event
main = main.replace(
    "window.addEventListener('load', async () => {",
    "(async () => {"
)
main = main.replace(
    "    initStaticLoadout(error);\n  }\n});",
    "    initStaticLoadout(error);\n  }\n})();"
)

modules['main.js'] = main

# Remove original scripts and manifests from html
html = re.sub(r'<script\b[^>]*>.*?</script>', '', html, flags=re.DOTALL)
html = re.sub(r'<link[^>]+(?:manifest|icon)[^>]*>', '', html)

# Replace Main Logo.png in CSS if present
if 'Main Logo.png' in assets:
    logo_data = f"data:image/png;base64,{assets['Main Logo.png'][1]}"
    html = html.replace("url('Main Logo.png')", f"url('{logo_data}')")

# Top review toolbar for direct jumping to Fighter Roster Select
toolbar = '''
<div id="bf-preview-nav" style="position:fixed;top:8px;left:50%;transform:translateX(-50%);z-index:999999;background:rgba(13,17,28,0.92);border:1px solid rgba(255,255,255,0.22);border-radius:12px;padding:6px 14px;color:#fff;font:12px system-ui,sans-serif;display:flex;gap:10px;align-items:center;box-shadow:0 6px 20px rgba(0,0,0,0.6);backdrop-filter:blur(6px);pointer-events:auto;">
  <span style="font-weight:900;letter-spacing:1px;color:#ffd166;">BOMBER FAN PREVIEW</span>
  <button id="btn-roster" style="cursor:pointer;background:#ff376f;color:#fff;border:0;border-radius:6px;padding:5px 10px;font-weight:700;font-size:11px;">ROSTER SELECT</button>
  <button id="btn-menu" style="cursor:pointer;background:#2446f5;color:#fff;border:0;border-radius:6px;padding:5px 10px;font-weight:700;font-size:11px;">TITLE SCREEN</button>
  <button id="btn-hide-nav" style="cursor:pointer;background:rgba(255,255,255,0.15);color:#ccc;border:0;border-radius:6px;padding:5px 8px;font-size:11px;">✕</button>
</div>
'''

# Client-side boot script
boot = r'''
const encodedAssets = ASSETS;
window.BFOfflineAssets = {};

// 1. Instantiate binary blobs and images
for (const [name, [type, data]] of Object.entries(encodedAssets)) {
  if (name.endsWith('.gltf')) continue;
  const binary = atob(data);
  const len = binary.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i);
  window.BFOfflineAssets[name] = URL.createObjectURL(new Blob([bytes], { type }));
}

// 2. Patch glTF internal buffer & image URIs
for (const [name, [type, data]] of Object.entries(encodedAssets)) {
  if (!name.endsWith('.gltf')) continue;
  const json = JSON.parse(atob(data));
  const base = name.slice(0, name.lastIndexOf('/') + 1);
  for (const resource of [...(json.buffers || []), ...(json.images || [])]) {
    if (resource.uri && window.BFOfflineAssets[base + resource.uri]) {
      resource.uri = window.BFOfflineAssets[base + resource.uri];
    }
  }
  window.BFOfflineAssets[name] = URL.createObjectURL(new Blob([JSON.stringify(json)], { type }));
}

// 3. Patch DOM src and CSS urls
for (const element of document.querySelectorAll('[src]')) {
  const value = decodeURIComponent(element.getAttribute('src'));
  if (window.BFOfflineAssets[value]) element.src = window.BFOfflineAssets[value];
}
for (const style of document.querySelectorAll('style')) {
  let css = style.textContent;
  for (const [name, url] of Object.entries(window.BFOfflineAssets)) {
    css = css.split(name).join(url).split(encodeURI(name)).join(url);
  }
  style.textContent = css;
}

// 4. Resolve module dependencies using Blob URLs
const modules = MODULES;
const urls = {};

// Order of module registration to resolve dependencies cleanly
const order = [
  'three.module.min.js',
  'three.core.min.js',
  'BufferGeometryUtils.js',
  'SkeletonUtils.js',
  'GLTFLoader.js',
  'roster-eyes.js',
  'arena-lighting.js',
  'pirate-water.js',
  'character-bootstrap.js',
  'main.js'
];

for (const name of order) {
  if (!modules[name]) continue;
  let code = modules[name];
  for (const [dependency, url] of Object.entries(urls)) {
    code = code.split("'./" + dependency + "'").join(JSON.stringify(url))
               .split('"./' + dependency + '"').join(JSON.stringify(url));
  }
  urls[name] = URL.createObjectURL(new Blob([code], { type: 'text/javascript' }));
}

// Setup preview navigation toolbar
document.getElementById('btn-hide-nav').onclick = () => document.getElementById('bf-preview-nav').remove();
document.getElementById('btn-roster').onclick = () => {
  const playBtn = document.querySelector('#menu .opt.go');
  if (playBtn) playBtn.click();
  else {
    const sel = document.getElementById('select');
    const menu = document.getElementById('menu');
    if (sel && menu) {
      menu.classList.add('hidden');
      sel.classList.remove('hidden');
    }
  }
};
document.getElementById('btn-menu').onclick = () => {
  const sel = document.getElementById('select');
  const menu = document.getElementById('menu');
  if (sel && menu) {
    sel.classList.add('hidden');
    menu.classList.remove('hidden');
  }
};

// 5. Boot modules
(async () => {
  await import(urls['character-bootstrap.js']);
  await import(urls['main.js']);
  console.log('Bomber Fan offline preview successfully booted.');
})().catch(e => {
  const p = document.createElement('div');
  p.innerHTML = '<b>Unable to boot game:</b> ' + e.message;
  p.style.cssText = 'position:fixed;top:80px;left:20px;right:20px;padding:16px;background:rgba(200,0,0,0.9);color:white;z-index:9999999;border-radius:8px;font-family:sans-serif;';
  document.body.append(p);
  console.error('Boot error:', e);
});
'''

boot = boot.replace('ASSETS', json.dumps(assets))\
           .replace('MODULES', json.dumps(modules))\
           .replace('</script', '<\\/script')

html = html.replace('</body>', toolbar + '<script>' + boot + '</script></body>')

# Output to artifacts directory for IDE right panel
target_artifact = artifacts_dir / 'live_preview.html'
target_artifact.write_text(html, encoding='utf-8')
print(f"Written artifact to {target_artifact} ({target_artifact.stat().st_size / 1024 / 1024:.2f} MB)")

# Also write to repo for convenience
target_local = root / 'live_preview.html'
target_local.write_text(html, encoding='utf-8')
print(f"Written local copy to {target_local} ({target_local.stat().st_size / 1024 / 1024:.2f} MB)")
