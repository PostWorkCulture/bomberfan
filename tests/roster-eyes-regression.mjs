import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {T,defs,loadCharacter,dispose,measure,addRosterEyes} from '../tools/character-qa.mjs';
import {EYE_STYLES} from '../assets/vendor/roster-eyes.js';

const args=process.argv.slice(2),out=args.includes('--export')?path.resolve(args[args.indexOf('--export')+1]):null;
const selected=args.includes('--id')?args[args.indexOf('--id')+1]:null;
assert.equal(Object.keys(EYE_STYLES).length,18);
assert.equal(EYE_STYLES['blue-demon'],undefined,'Abyss is excluded');
assert.equal(EYE_STYLES['bomber-og'],undefined,'BomberOG is excluded');
const blank=new T.Group();
for(const id of ['blue-demon','bomber-og'])assert.equal(addRosterEyes(blank,{id}),false);
assert.equal(blank.children.length,0,'excluded fighters are not modified');
const results=[];
globalThis.window={};
await import('../assets/vendor/character-bootstrap.js');
assert.equal(typeof window.BFCharacter3D.addRosterEyes,'function','production bootstrap exposes eye customization after the atlas loads');
for(const def of defs.filter(d=>EYE_STYLES[d.id]&&(!selected||d.id===selected))){
  const api=await loadCharacter(def),{gltf,makeModel,pose,exportVariant}=api;
  const originalGeometry=new Set(),originalMaterial=new Set(),originalTexture=new Set();
  const fingerprint=()=>{
    const h=createHash('sha256');
    gltf.scene.traverse(o=>{if(!o.isMesh)return;originalGeometry.add(o.geometry);originalMaterial.add(o.material);if(o.material.map)originalTexture.add(o.material.map);
      for(const a of Object.values(o.geometry.attributes))h.update(Buffer.from(a.array.buffer,a.array.byteOffset,a.array.byteLength));h.update(Buffer.from(o.geometry.index.array.buffer));});
    for(const c of gltf.animations)for(const track of c.tracks){h.update(c.name+track.name);h.update(Buffer.from(track.times.buffer));h.update(Buffer.from(track.values.buffer));}
    return h.digest('hex');
  };
  const beforeHash=fingerprint(),before=makeModel(false),after=makeModel(),second=makeModel();
  const face=after.getObjectByName('RosterEyes');
  assert.equal(face?.userData.eyeCount,2,`${def.id}: exactly two replacement eyes`);
  assert.equal(face.parent.name,'Head');
  assert.equal(face.children.length,2,`${def.id}: exactly two continuous eye surfaces`);
  assert.equal(addRosterEyes(after,def),false,`${def.id}: customization is idempotent`);
  for(const eye of face.children){
    const peer=second.getObjectByName(eye.name);
    assert.equal(eye.geometry,peer.geometry,'eye geometry is cached across instances');
    assert.equal(eye.material.map,peer.material.map,'procedural eye artwork is cached across instances');
    assert.notEqual(eye.material,peer.material,'each instance owns its material');
    let disposed=0;
    eye.geometry.addEventListener('dispose',()=>disposed++);
    eye.material.map.addEventListener('dispose',()=>disposed++);
    eye.userData.cachedResourceDisposals=()=>disposed;
  }
  const a=measure(before),b=measure(after);
  assert.equal(a.lights,b.lights,'no additional lights');
  assert.ok(b.triangles-a.triangles<=2600,`${def.id}: triangle budget`);
  const otherMaterials=new Set();second.traverse(o=>{if(o.material)otherMaterials.add(o.material);});
  after.traverse(o=>{if(!o.isMesh)return;assert.ok(!originalMaterial.has(o.material));assert.ok(!otherMaterials.has(o.material));
    if(!o.userData.sharedModelGeometry)assert.ok(!originalGeometry.has(o.geometry));
    for(const attr of Object.values(o.geometry.attributes))for(const n of attr.array)assert.ok(Number.isFinite(n));
  });
  const posed=makeModel(false),head=posed.getObjectByName('Head');
  head.rotation.z+=.8;posed.scale.multiplyScalar(1.4);posed.updateMatrixWorld(true);addRosterEyes(posed,def);
  for(const child of face.children){
    const actual=posed.getObjectByName('RosterEyes').getObjectByName(child.name);
    assert.deepEqual(actual.geometry.attributes.position.array,child.geometry.attributes.position.array,'eye shape is independent of current Head pose');
    assert.deepEqual(actual.position.toArray(),child.position.toArray(),'eye placement is independent of current Head pose');
    assert.deepEqual(actual.quaternion.toArray(),child.quaternion.toArray(),'eye orientation is independent of current Head pose');
  }
  dispose(posed);
  let samples=0;
  for(const clip of gltf.animations){
    const model=makeModel(),mixer=new T.AnimationMixer(model);mixer.clipAction(clip).play();
    for(const time of [0,clip.duration*.5,Math.max(0,clip.duration-.001)]){
      mixer.setTime(time);model.updateMatrixWorld(true);
      model.traverseVisible(o=>{if(!o.isMesh)return;if(o.isSkinnedMesh)o.skeleton.update();const v=new T.Vector3();
        for(let i=0;i<o.geometry.attributes.position.count;i++){o.getVertexPosition(i,v).applyMatrix4(o.matrixWorld);assert.ok(Number.isFinite(v.length())&&v.length()<10,`${def.id}/${clip.name}: finite bounded posed geometry`);}});
      assert.equal(model.getObjectByName('RosterEyes').parent.name,'Head');samples++;
    }
    mixer.stopAllAction();mixer.uncacheRoot(model);dispose(model);
  }
  if(out){
    const bm=pose(before,'Idle'),am=pose(after,'Idle');
    const doc={metadata:{id:def.id,name:def.name,style:EYE_STYLES[def.id].label,refs:EYE_STYLES[def.id].refs,scope:'actual posed geometry; CPU export; no GPU claims'},variants:{before:exportVariant(before),after:exportVariant(after)}};
    fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,def.id+'.json'),JSON.stringify(doc));
    bm.stopAllAction();bm.uncacheRoot(before);am.stopAllAction();am.uncacheRoot(after);
  }
  let sharedDisposals=0;for(const resource of [...originalGeometry,...originalTexture])resource.addEventListener('dispose',()=>sharedDisposals++);
  const owned=new Map();after.traverse(o=>{if(!o.isMesh)return;for(const r of [o.material,...(!o.userData.sharedModelGeometry?[o.geometry]:[])]){if(owned.has(r))continue;owned.set(r,0);r.addEventListener('dispose',()=>owned.set(r,owned.get(r)+1));}});
  dispose(before);dispose(after);dispose(second);dispose(after);
  for(const eye of face.children)assert.equal(eye.userData.cachedResourceDisposals(),0,'cached eye geometry and atlas survive instance disposal');
  assert.equal(sharedDisposals,0,`${def.id}: cached geometry/textures survived disposal`);
  for(const n of owned.values())assert.equal(n,1,'owned resources disposed once');
  assert.equal(fingerprint(),beforeHash,`${def.id}: source geometry, rig and animation data preserved`);
  const result={id:def.id,name:def.name,style:EYE_STYLES[def.id].label,clips:gltf.animations.length,samples,addedMeshes:b.meshes-a.meshes,addedTriangles:b.triangles-a.triangles};
  results.push(result);console.log('PASS '+JSON.stringify(result));
}
console.log(JSON.stringify({status:'PASS',fighters:results.length,animationSamples:results.reduce((s,r)=>s+r.samples,0),results}));
