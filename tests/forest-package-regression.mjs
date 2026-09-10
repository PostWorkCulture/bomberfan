// Parse the delivered HTML and every embedded ES module without executing a browser.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const path=process.argv[2]||'../deliverables/Bomberfan-Forest-Review.html';
const html=fs.readFileSync(path,'utf8');
const source=[...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].at(-1)[1];
new vm.Script(source);
const assets=JSON.parse(source.match(/const encodedAssets=(.*);\nwindow.BFOfflineAssets/)[1]);
const modules=JSON.parse(source.match(/const modules=(.*),urls=\{\};/)[1]);
const names=new Set();
for(const [name,code]of Object.entries(modules)){
 const m=new vm.SourceTextModule(code);for(const dep of m.dependencySpecifiers)assert.ok(names.has(dep.replace('./','')),name+' dependency '+dep+' already available');names.add(name);
}
let models=0;
for(const [name,[mime,data]]of Object.entries(assets)){
 const bytes=Buffer.from(data,'base64');assert.ok(bytes.length>0);
 if(name.endsWith('.gltf')){models++;const gltf=JSON.parse(bytes);for(const resource of [...(gltf.buffers||[]),...(gltf.images||[])])assert.ok(assets[name.slice(0,name.lastIndexOf('/')+1)+resource.uri],name+' resource embedded');}
}
assert.equal(models,20);assert.ok(!modules['main.js'].includes('${def.portrait}?v=${BUILD_ID}'),'blob portraits have no invalid cache suffix');
assert.ok(!modules['main.js'].includes("window.addEventListener('load', async"),'dynamic import cannot miss load event');
assert.ok(modules['main.js'].includes("g.opts.level = 'forest';"));
console.log(`PASS standalone package: ${models} complete models, ${Object.keys(assets).length} assets, ${names.size} modules parsed, dependency order and offline boot verified. Browser execution remains unverified.`);
