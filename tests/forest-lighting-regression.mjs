import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as T from '../assets/vendor/three.module.min.js';
import {ForestLighting,bevelBox,forestAssets} from '../assets/vendor/forest-lighting.js';
const names=['ground','soft','hard','hardTop','wall','wallTop','border'];
const mat=Object.fromEntries(names.map(n=>[n,new T.MeshStandardMaterial({roughness:.8,metalness:.05})]));
for(const n of ['ground','ground-normal','wood','stone','ground-ao','ground-bounce']){
  const bytes=fs.readFileSync(new URL(`../assets/forest/${n}.png`,import.meta.url));
  assert.equal(bytes.subarray(1,4).toString(),'PNG');
  const texture=new T.Texture();texture.userData.forestShared=true;forestAssets[n]=texture;
}
const scene=new T.Scene();scene.background=new T.Color();scene.fog=new T.Fog(0,26,44);
const key=new T.DirectionalLight(), fill=new T.DirectionalLight(),hemi=new T.HemisphereLight();
const renderer={render(){},toneMappingExposure:1.15};
const light=new ForestLighting({scene,key,fill,hemi,renderer,mat});
const forest={id:'forest',sky:0x0e1a12},beach={id:'beach',sky:0x07293f};
let disposed=0;forestAssets.ground.addEventListener('dispose',()=>disposed++);
for(let i=0;i<12;i++){
  light.apply(forest);assert.equal(light.enabled,true);
  assert.equal(mat.ground.aoMap,forestAssets['ground-ao']);
  const geo=new T.PlaneGeometry(15,13);light.prepareFloor(geo);assert.equal(geo.attributes.uv1.count,4);
  assert.equal(mat.soft.aoMap,null,'crates never have baked static occlusion');
  light.apply(forest);assert.equal(disposed,0,'re-applying Forest preserves the shared surface');
  // World regenerates the transient palette maps before changing level.
  mat.ground.map=new T.Texture();mat.soft.map=new T.Texture();
  light.apply(beach);assert.equal(light.enabled,false);assert.equal(scene.environment,null);
  assert.equal(mat.ground.aoMap,null);assert.equal(mat.ground.lightMap,null);assert.equal(mat.ground.normalMap,null);
  assert.equal(key.intensity,2);assert.equal(renderer.toneMappingExposure,1.15);
  assert.equal(mat.hard.map,null);assert.equal(mat.hard.roughness,.8);
}
light.apply(forest);assert.equal(key.shadow.mapSize.x,2048);
light.adapt(29);assert.equal(light.tier,'high');light.adapt(29);assert.equal(light.tier,'balanced');assert.equal(key.shadow.mapSize.x,1024);
const phone=new ForestLighting({scene,key,fill,hemi,renderer,mat,mobile:true});assert.equal(phone.tier,'balanced');
const original=new ForestLighting({scene,key,fill,hemi,renderer,mat,mode:'original'});original.apply(forest);
assert.equal(original.enabled,false);assert.equal(original.geometry(1,1,1).attributes.position.count,24);
for(const [w,h,d,r] of [[.98,1,.98,.07],[1,.14,1,.045],[.92,.92,.92,.055]]){
  const geo=bevelBox(w,h,d,r),v=geo.attributes.position,n=geo.attributes.normal;
  for(let i=0;i<v.count;i++){
    assert.ok(Math.abs(v.getX(i))<=w/2+1e-6&&Math.abs(v.getY(i))<=h/2+1e-6&&Math.abs(v.getZ(i))<=d/2+1e-6,'mesh stays inside collision footprint');
    assert.ok(Math.abs(Math.hypot(n.getX(i),n.getY(i),n.getZ(i))-1)<1e-5,'finite unit normal');
  }
}
light.dispose();light.dispose();
console.log('PASS Forest: 12 map-return cycles, shared assets, baked/dynamic separation, baseline restoration, adaptive and mobile tiers, bevel normals/collision footprints. GPU not simulated.');
