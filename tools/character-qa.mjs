// CPU model loading/export for repeatable artwork inspection. No browser/GPU.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import * as T from '../assets/vendor/three.module.min.js';
import {GLTFLoader} from '../assets/vendor/GLTFLoader.js';
import {clone} from '../assets/vendor/SkeletonUtils.js';
import {addRosterEyes} from '../assets/vendor/roster-eyes.js';
export {T,addRosterEyes};
export const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const modules=process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES||'/opt/codex/runtimes/codex-primary-runtime/dependencies/node/node_modules';
const require=createRequire(path.join(modules,'package.json'));
const {createCanvas,loadImage}=require('@napi-rs/canvas');
globalThis.document ||= {createElement:()=>createCanvas(256,128)};
const eyeImage=await loadImage(path.join(repo,'assets/characters/roster-eye-atlas.png'));
const eyeCanvas=createCanvas(eyeImage.width,eyeImage.height);eyeCanvas.getContext('2d').drawImage(eyeImage,0,0);
const browserTextureLoad=T.TextureLoader.prototype.load;
T.TextureLoader.prototype.load=function(url,onLoad,...args){
  if(String(url).endsWith('/roster-eye-atlas.png')){
    const texture=new T.Texture(eyeCanvas);texture.needsUpdate=true;queueMicrotask(()=>onLoad?.(texture));return texture;
  }
  return browserTextureLoad.call(this,url,onLoad,...args);
};
const html=fs.readFileSync(path.join(repo,'index.html'),'utf8');
export const defs=vm.runInNewContext(html.slice(html.indexOf('const PLAYER_DEFS = ['),html.indexOf('// Fixed spawn corners'))+';PLAYER_DEFS');
const start=html.indexOf('const CharacterModels = (() => {');
const end=html.indexOf('\n})();',start)+'\n})();'.length;
const code=html.slice(start,end).replace('return { create, dispose };','return { create, dispose, _qa: { addFighterDetails, prepareMaterial } };');
const context=vm.createContext({THREE:T,World:{renderer:null,MAT:{bomb:null}},console});
vm.runInContext(code+';globalThis.qa = CharacterModels;',context);
const {dispose,_qa:{addFighterDetails,prepareMaterial}}=context.qa;
export {dispose};
export function measure(model){
  let meshes=0,triangles=0,lights=0;
  model.traverseVisible(o=>{if(o.isLight)lights++;if(o.isMesh){meshes++;triangles+=(o.geometry.index?.count||o.geometry.attributes.position.count)/3;}});
  return {meshes,triangles,lights};
}
export async function loadCharacter(def){
  const modelPath=path.join(repo,def.model),gltfJson=JSON.parse(fs.readFileSync(modelPath,'utf8'));
  const atlas=await loadImage(path.join(path.dirname(modelPath),gltfJson.images[0].uri));
  const canvas=createCanvas(atlas.width,atlas.height),ctx=canvas.getContext('2d');
  ctx.drawImage(atlas,0,0);const pixels=ctx.getImageData(0,0,atlas.width,atlas.height).data;
  globalThis.self=globalThis;
  globalThis.ProgressEvent ||= class ProgressEvent {constructor(type,init={}){this.type=type;Object.assign(this,init);}};
  const original=T.TextureLoader.prototype.load;
  T.TextureLoader.prototype.load=function(url,onLoad){const t=new T.Texture(atlas);t.needsUpdate=true;queueMicrotask(()=>onLoad?.(t));return t;};
  for(const b of gltfJson.buffers)b.uri='data:application/octet-stream;base64,'+fs.readFileSync(path.join(path.dirname(modelPath),b.uri)).toString('base64');
  let gltf;try{gltf=await new GLTFLoader().parseAsync(JSON.stringify(gltfJson),'');}finally{T.TextureLoader.prototype.load=original;}
  const RT={THREE:T,GLTFLoader,clone,addRosterEyes};
  function makeModel(custom=true){
    const model=clone(gltf.scene);
    model.traverse(o=>{if(!o.isMesh)return;o.userData.sharedModelGeometry=true;o.material=Array.isArray(o.material)?o.material.map(m=>prepareMaterial(RT,m,def)):prepareMaterial(RT,o.material,def);});
    model.updateMatrixWorld(true);const bounds=new T.Box3().setFromObject(model),size=bounds.getSize(new T.Vector3());
    model.scale.setScalar(Math.min(.72/size.x,.95/size.y,.72/size.z));model.updateMatrixWorld(true);
    bounds.setFromObject(model);const centre=bounds.getCenter(new T.Vector3());
    model.position.set(-centre.x,-bounds.min.y+(def.flying?.11:0),-centre.z);
    addFighterDetails(custom?RT:{...RT,addRosterEyes:()=>false},model,def);
    model.updateMatrixWorld(true);return model;
  }
  function pose(model,name,time=.65){
    const clip=gltf.animations.find(c=>c.name===name)||gltf.animations.find(c=>/idle/i.test(c.name))||gltf.animations[0];
    const mixer=new T.AnimationMixer(model);mixer.clipAction(clip).play();mixer.setTime(Math.min(time,clip.duration-.00001));
    model.updateMatrixWorld(true);model.traverse(o=>{if(o.isSkinnedMesh)o.skeleton.update();});return mixer;
  }
  const srgbLinear = value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
const round = value => Math.round(value * 1e7) / 1e7;
function materialRecord(material) {
  return {
    name: material.name || '', type: material.type,
    color: material.color?.toArray() || [1, 1, 1],
    emissive: material.emissive?.toArray() || [0, 0, 0],
    emissiveIntensity: material.emissiveIntensity ?? 0,
    roughness: material.roughness ?? 1, metalness: material.metalness ?? 0,
    opacity: material.opacity ?? 1, transparent: !!material.transparent,
    side: material.side, vertexColors: !!material.vertexColors,
  };
}
function exportVariant(model) {
  const meshes = [];
  const bounds = new T.Box3();
  model.updateMatrixWorld(true);
  model.traverseVisible(object => {
    if (!object.isMesh) return;
    if (object.isSkinnedMesh) object.skeleton.update();
    const geometry = object.geometry;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    const material = materials[0];
    const procedural = !!material.map?.userData.sharedEyeTexture;
    const position = geometry.getAttribute('position'), normal = geometry.getAttribute('normal');
    const uv = geometry.getAttribute('uv'), vertexColor = geometry.getAttribute('color');
    const positions = [], normals = [], colors = [], emissiveColors = [];
    const point = new T.Vector3(), direction = new T.Vector3();
    const worldNormalMatrix = new T.Matrix3().getNormalMatrix(object.matrixWorld);
    const skinIndex = geometry.getAttribute('skinIndex'), skinWeight = geometry.getAttribute('skinWeight');
    const boneMatrix = new T.Matrix4(), skinMatrix = new T.Matrix4();
    const skinNormalMatrix = new T.Matrix3();
    for (let i = 0; i < position.count; i++) {
      object.getVertexPosition(i, point).applyMatrix4(object.matrixWorld);
      bounds.expandByPoint(point);
      positions.push(round(point.x), round(point.y), round(point.z));
      direction.set(normal?.getX(i) || 0, normal?.getY(i) || 0, normal?.getZ(i) || 0);
      if (object.isSkinnedMesh) {
        skinMatrix.elements.fill(0);
        for (let component = 0; component < 4; component++) {
          const weight = skinWeight.getComponent(i, component);
          if (!weight) continue;
          const joint = skinIndex.getComponent(i, component);
          boneMatrix.multiplyMatrices(object.skeleton.bones[joint].matrixWorld, object.skeleton.boneInverses[joint]);
          for (let element = 0; element < 16; element++) skinMatrix.elements[element] += boneMatrix.elements[element] * weight;
        }
        skinMatrix.premultiply(object.bindMatrixInverse).multiply(object.bindMatrix);
        skinNormalMatrix.setFromMatrix4(skinMatrix);
        direction.applyMatrix3(skinNormalMatrix);
      }
      direction.applyMatrix3(worldNormalMatrix).normalize();
      assert.ok(Number.isFinite(direction.x) && Number.isFinite(direction.y) && Number.isFinite(direction.z), `${object.name}: normals are finite`);
      normals.push(round(direction.x), round(direction.y), round(direction.z));
      const color = material.color?.clone() || new T.Color(1, 1, 1);
      const emissive = material.emissive?.clone().multiplyScalar(material.emissiveIntensity ?? 0) || new T.Color(0, 0, 0);
      if (material.vertexColors && vertexColor) {
        color.r *= vertexColor.getX(i); color.g *= vertexColor.getY(i); color.b *= vertexColor.getZ(i);
      }
      if (material.map && uv && !procedural) {
        const x = Math.min(atlas.width - 1, Math.max(0, Math.floor(uv.getX(i) * atlas.width)));
        const v = material.map.flipY ? 1 - uv.getY(i) : uv.getY(i);
        const y = Math.min(atlas.height - 1, Math.max(0, Math.floor(v * atlas.height)));
        const pixel = (y * atlas.width + x) * 4;
        color.r *= srgbLinear(pixels[pixel] / 255); color.g *= srgbLinear(pixels[pixel + 1] / 255); color.b *= srgbLinear(pixels[pixel + 2] / 255);
        if (material.emissiveMap === material.map) {
          emissive.r *= srgbLinear(pixels[pixel] / 255); emissive.g *= srgbLinear(pixels[pixel + 1] / 255); emissive.b *= srgbLinear(pixels[pixel + 2] / 255);
        }
      }
      assert.ok(Number.isFinite(color.r) && Number.isFinite(color.g) && Number.isFinite(color.b), `${object.name}: colours are finite`);
      colors.push(round(color.r), round(color.g), round(color.b));
      emissiveColors.push(round(emissive.r), round(emissive.g), round(emissive.b));
    }
    meshes.push({
      name: object.name, positions, normals, colors, emissiveColors,
      indices: geometry.index ? Array.from(geometry.index.array) : Array.from({ length: position.count }, (_, i) => i),
      material: materialRecord(material), materials: materials.map(materialRecord),
      groups: geometry.groups.map(group => ({ ...group })),
      ...(procedural ? {uvs:Array.from(uv.array),texturePNG:material.map.image.toBuffer('image/png').toString('base64'),textureFlipY:material.map.flipY,textureEmissive:material.emissiveMap===material.map} : {}),
    });
  });
  return { bounds: { min: bounds.min.toArray(), max: bounds.max.toArray() }, counts: measure(model), meshes };
}

  return {gltf,makeModel,pose,exportVariant};
}
