"""Package the actual evaluation game as one offline HTML; no external requests."""
from pathlib import Path
import json,base64,re
root=Path(__file__).resolve().parents[1]
out=root.parent/'deliverables';out.mkdir(exist_ok=True)
mimes={'.png':'image/png','.webp':'image/webp','.jpg':'image/jpeg','.bin':'application/octet-stream','.gltf':'model/gltf+json'}
assets={}
for path in list((root/'assets/characters').iterdir())+list((root/'assets/portraits').iterdir())+list((root/'assets/forest').iterdir())+list(root.glob('*.png')):
 if path.suffix in mimes: assets[str(path.relative_to(root))]=[mimes[path.suffix],base64.b64encode(path.read_bytes()).decode()]
modules={}
for name in ['three.core.min.js','three.module.min.js','BufferGeometryUtils.js','SkeletonUtils.js','GLTFLoader.js','roster-eyes.js','forest-lighting.js','character-bootstrap.js']:
 text=(root/'assets/vendor'/name).read_text()
 text=text.replace("new URL('../characters/roster-eye-atlas.png',import.meta.url).href", "window.BFOfflineAssets['assets/characters/roster-eye-atlas.png']")
 text=text.replace('new URL(`../forest/${name}.png`, import.meta.url).href',"window.BFOfflineAssets['assets/forest/'+name+'.png']")
 modules[name]=text
html=(root/'forest-preview.html').read_text()
main=re.search(r'<script type="module">(.*?)</script>',html,re.S).group(1)
main=main.replace('${def.portrait}?v=${BUILD_ID}', '${def.portrait}')
main=main.replace('loader.loadAsync(def.model)', 'loader.loadAsync(window.BFOfflineAssets[def.model] || def.model)')
for p in assets:
 if p.startswith('assets/portraits/'):
  main=main.replace("'"+p+"'",'window.BFOfflineAssets['+json.dumps(p)+']')
main=main.replace("if (new URLSearchParams(window.location.search).has('forestReview')) g.opts.level = 'forest';", "g.opts.level = 'forest';")
main=main.replace("window.addEventListener('load', async () => {", "(async () => {")
main=main.replace("    initStaticLoadout(error);\n  }\n});", "    initStaticLoadout(error);\n  }\n})();")
main=main.replace("'./assets/vendor/three.module.min.js'", "'./three.module.min.js'").replace("'./assets/vendor/forest-lighting.js'", "'./forest-lighting.js'")
modules['main.js']=main
html=re.sub(r'<script\b[^>]*>.*?</script>','',html,flags=re.S)
html=re.sub(r'<link[^>]+(?:manifest|icon)[^>]*>','',html)
# Overlay belongs only to the review artifact, not the main game UI.
bar='''<aside id="forest-review-bar" style="position:fixed;top:8px;left:50%;transform:translateX(-50%);z-index:99999;background:#12271eee;border:1px solid #6d8963;border-radius:12px;padding:9px 12px;color:#fff;font:12px system-ui;display:flex;gap:8px;align-items:center;max-width:98vw;flex-wrap:wrap"><b>FOREST REVIEW</b><button data-light="original">Original</button><button data-light="auto">Upgraded · Auto</button><button data-light="balanced">Balanced</button><button data-light="high">High</button><button id="hide-review">Hide toolbar</button></aside>'''
boot=r'''
const encodedAssets=ASSETS;
window.BFOfflineAssets={};
for(const [name,[type,data]] of Object.entries(encodedAssets)){
 if(name.endsWith('.gltf'))continue;
 const bytes=Uint8Array.from(atob(data),c=>c.charCodeAt(0));
 window.BFOfflineAssets[name]=URL.createObjectURL(new Blob([bytes],{type}));
}
for(const [name,[type,data]] of Object.entries(encodedAssets)){
 if(!name.endsWith('.gltf'))continue;
 const json=JSON.parse(atob(data)),base=name.slice(0,name.lastIndexOf('/')+1);
 for(const resource of [...(json.buffers||[]),...(json.images||[])])if(resource.uri)resource.uri=window.BFOfflineAssets[base+resource.uri];
 window.BFOfflineAssets[name]=URL.createObjectURL(new Blob([JSON.stringify(json)],{type}));
}
for(const element of document.querySelectorAll('[src]')){
 const value=decodeURIComponent(element.getAttribute('src'));if(window.BFOfflineAssets[value])element.src=window.BFOfflineAssets[value];
}
for(const style of document.querySelectorAll('style')){
 let css=style.textContent;for(const [name,url] of Object.entries(window.BFOfflineAssets))css=css.split(name).join(url).split(encodeURI(name)).join(url);style.textContent=css;
}
const modules=MODULES,urls={};
for(const [name,source] of Object.entries(modules)){
 let code=source;
 for(const [dependency,url] of Object.entries(urls))code=code.split("'./"+dependency+"'").join(JSON.stringify(url)).split('"./'+dependency+'"').join(JSON.stringify(url));
 urls[name]=URL.createObjectURL(new Blob([code],{type:'text/javascript'}));
}
const mode=new URLSearchParams(location.search).get('lighting')||'auto';
for(const b of document.querySelectorAll('[data-light]')){b.style.cssText='border:0;border-radius:6px;padding:7px;cursor:pointer;background:'+(b.dataset.light===mode?'#cee5a3':'#344c3d')+';color:'+(b.dataset.light===mode?'#12271e':'white');b.addEventListener('click',()=>{const url=new URL(location.href);url.searchParams.set('lighting',b.dataset.light);location.href=url.href;});}
document.getElementById('hide-review').onclick=()=>document.getElementById('forest-review-bar').remove();
(async()=>{await import(urls['character-bootstrap.js']);await import(urls['main.js']);})().catch(e=>{const p=document.createElement('p');p.textContent='Unable to start review: '+e.message;p.style.cssText='position:fixed;top:80px;color:white;z-index:999999';document.body.append(p);console.error(e)});
'''
# JSON embedded in HTML must not terminate its enclosing script.
boot=boot.replace('ASSETS',json.dumps(assets)).replace('MODULES',json.dumps(modules)).replace('</script','<\\/script')
html=html.replace('</body>',bar+'<script>'+boot+'</script></body>')
path=out/'Bomberfan-Forest-Review.html';path.write_text(html)
print(path, path.stat().st_size)
