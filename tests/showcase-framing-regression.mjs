import fs from 'node:fs';import assert from 'node:assert/strict';
import {T,defs,loadCharacter} from '../tools/character-qa.mjs';
const source=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const a=source.indexOf('  // One visible showcase model only.'),b=source.indexOf('  function renderPreview()',a);
const fit=new Function('THREE','lerp',source.slice(a,b)+';return fitShowcase;')(T,(a,b,t)=>a+(b-a)*t);
let checks=0;let minFill=1,maxExtent=0;
for(const def of defs){
 let fighterMin=1;
 const loaded=await loadCharacter(def);const model=loaded.makeModel();
 const group=new T.Group();group.add(model);group.userData.combatClass=def.id;group.userData.modelRoot=model;group.userData.modelReady=true;
 const f=(def.id==='bomber-og'?.8:1)*(def.flying?.68:.60);group.scale.set(2.35*.75*f,2.65*.75*f,2.35*.75*f);group.position.y=-.4;
 const turn=new T.Group();turn.rotation.y=-.28;turn.add(group);turn.updateMatrixWorld(true);
 const basePose=loaded.pose(model,'Idle',.01);
 for(const aspect of [.65,1,1.8,2.8]){
  loaded.pose(model,'Idle',.01);
  const stage={mesh:group,cam:new T.PerspectiveCamera(29,aspect,.1,40)};fit(stage,aspect,.88);stage.cam.updateMatrixWorld(true);
  for(const name of new Set(['Idle',def.expression,def.altExpression].filter(Boolean))){
   for(const t of [.1,.55,1.1]){
    const mixer=loaded.pose(model,name,t);turn.updateMatrixWorld(true);
    for(let settle=0;settle<25;settle++)fit(stage,aspect,.88);stage.cam.updateMatrixWorld(true);
    let loX=Infinity,hiX=-Infinity,loY=Infinity,hiY=-Infinity;
    model.traverseVisible(o=>{if(!o.isMesh)return;const p=o.geometry.attributes.position,v=new T.Vector3();for(let i=0;i<p.count;i++){
      o.getVertexPosition(i,v);v.applyMatrix4(o.matrixWorld).project(stage.cam);loX=Math.min(loX,v.x);hiX=Math.max(hiX,v.x);loY=Math.min(loY,v.y);hiY=Math.max(hiY,v.y);
    }});
    const extent=Math.max(Math.abs(loX),Math.abs(hiX),Math.abs(loY),Math.abs(hiY));maxExtent=Math.max(maxExtent,extent);
    assert.ok(extent<1.02,`${def.name} ${name} ${t} aspect ${aspect}: clipped ${extent}`);
    fighterMin=Math.min(fighterMin,Math.max((hiY-loY)/2,(hiX-loX)/2));
    minFill=Math.min(minFill,Math.max((hiY-loY)/2,(hiX-loX)/2));checks++;mixer.stopAllAction();mixer.uncacheRoot(model);
   }
  }
 }
 console.log(def.name,(fighterMin*100).toFixed(1));
 basePose.stopAllAction();
}
console.log(`PASS ${checks} actual model/pose/viewport framing checks; min dominant-axis fill ${(minFill*100).toFixed(1)}%, max NDC extent ${maxExtent.toFixed(3)}. Projection checks, not GPU rendering.`);
