import assert from 'node:assert/strict';import fs from 'node:fs';
import * as T from '../assets/vendor/three.module.min.js';
import {ArenaLighting,ArenaPost,ARENA_PROFILES,arenaAssets} from '../assets/vendor/arena-lighting.js';
const layouts=JSON.parse(fs.readFileSync(new URL('../assets/lighting/layouts.json',import.meta.url)));
assert.deepEqual(Object.keys(ARENA_PROFILES).sort(),Object.keys(layouts).sort());
for(const id of Object.keys(ARENA_PROFILES))for(const suffix of ['ao','bounce']){
 const name=id==='forest'?'ground':id,dir=id==='forest'?'forest':'lighting';
 const bytes=fs.readFileSync(new URL(`../assets/${dir}/${name}-${suffix}.png`,import.meta.url));
 assert.equal(bytes.subarray(1,4).toString(),'PNG');
 const tex=new T.Texture();tex.channel=1;arenaAssets[name+'-'+suffix]=tex;
}
const scene=new T.Scene();scene.background=new T.Color();scene.fog=new T.Fog(0,26,44);
const key=new T.DirectionalLight(),fill=new T.DirectionalLight(),hemi=new T.HemisphereLight();
const mat=Object.fromEntries(['ground','soft','hard','hardTop','wall','wallTop','border'].map(n=>[n,new T.MeshStandardMaterial()]));
const renderer={render(){},toneMappingExposure:1.15};
const light=new ArenaLighting({scene,key,fill,hemi,mat,renderer});
for(let pass=0;pass<3;pass++)for(const[id,p]of Object.entries(ARENA_PROFILES)){
 light.apply({id,sky:layouts[id].sky,cols:layouts[id].cols,rows:layouts[id].rows});assert.ok(light.enabled);assert.equal(key.color.getHex(),p.key);
 assert.equal(renderer.toneMappingExposure,p.exposure);
 assert.equal(mat.ground.aoMap,arenaAssets[(id==='forest'?'ground':id)+'-ao']);
 assert.equal(mat.soft.aoMap,null,'moving/destructible objects are not baked');
 // Test arbitrary deck offsets under a rotated menu root. UVs must stay board-relative.
 const root=new T.Group();root.rotation.y=.87;
 const floor=new T.Mesh(new T.PlaneGeometry(5,5),mat.ground);floor.rotation.x=-Math.PI/2;floor.position.set(-4,.002,0);root.add(floor);
 light.prepareFloors(root);const uv=floor.geometry.attributes.uv1;
 assert.ok(Math.abs(uv.getX(0)-(-6.5+(layouts[id].cols||15)/2)/(layouts[id].cols||15))<1e-6);assert.ok(Math.abs(uv.getY(0)-(9/13))<1e-6);
 assert.equal(light.geometry(.92,.92,.92,.055).attributes.position.count,150);
}
light.apply({id:'unknown',sky:0});assert.equal(light.enabled,false);assert.equal(mat.ground.aoMap,null);assert.equal(renderer.toneMappingExposure,1.15);
// Full post chain and failure restoration, without pretending this compiles GPU shaders.
let draws=0;const target={name:'previous'};
const r={toneMapping:T.ACESFilmicToneMapping,current:target,getDrawingBufferSize(v){return v.set(800,600)},getRenderTarget(){return this.current},setRenderTarget(t){this.current=t},render(){draws++}};
const post=new ArenaPost(r);post.render(new T.Scene(),new T.Camera());assert.equal(draws,5);assert.equal(r.current,target);assert.equal(r.toneMapping,T.ACESFilmicToneMapping);assert.equal(post.a.width,200);assert.equal(post.a.height,150);
r.render=()=>{throw Error('test draw failure')};assert.throws(()=>post.render(scene,new T.Camera()));assert.equal(r.current,target);assert.equal(r.toneMapping,T.ACESFilmicToneMapping);post.dispose();light.dispose();
console.log('PASS arena lighting: all 7 profiles across 3 map cycles, distinct static maps, offset-deck UVs, rotating-root invariance, geometry, HDR pass sizing and render-state restoration. GPU execution not measured.');
