// Real Three.js character/skeleton checks and a posed mesh export for offline
// review. This does not create a browser or claim GPU/device/FPS coverage.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const positional = args.filter((arg, index) => !arg.startsWith('--') && !args[index - 1]?.startsWith('--'));
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const parent = path.resolve(here, '..');
const inferredRepo = fs.existsSync(path.join(parent, 'index.html')) ? parent : path.join(parent, 'bomberfan');
const repo = path.resolve(positional[0] || inferredRepo);
const output = path.resolve(positional[1] || path.join(os.tmpdir(), 'bomberfan-abyss-geometry.json'));
const poseName = option('--clip', 'Idle');
const poseTime = Number(option('--time', '0.65'));
const modules = process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES || '/opt/codex/runtimes/codex-primary-runtime/dependencies/node/node_modules';
const require = createRequire(path.join(modules, 'package.json'));
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const T = await import(pathToFileURL(path.join(repo, 'assets/vendor/three.module.min.js')));
const { GLTFLoader } = await import(pathToFileURL(path.join(repo, 'assets/vendor/GLTFLoader.js')));
const { clone } = await import(pathToFileURL(path.join(repo, 'assets/vendor/SkeletonUtils.js')));
const RT = { THREE: T, GLTFLoader, clone };
const modelPath = path.join(repo, 'assets/characters/blue-demon.gltf');
const gltfJson = JSON.parse(fs.readFileSync(modelPath, 'utf8'));
const imagePath = path.join(path.dirname(modelPath), gltfJson.images[0].uri);
const atlas = await loadImage(imagePath);
const imageCanvas = createCanvas(atlas.width, atlas.height);
const imageContext = imageCanvas.getContext('2d');
imageContext.drawImage(atlas, 0, 0);
const pixels = imageContext.getImageData(0, 0, atlas.width, atlas.height).data;

// GLTFLoader still parses its actual buffers, attributes, rig, tracks and
// materials. Only browser image decoding is replaced by a local PNG decoder.
globalThis.self = globalThis;
globalThis.ProgressEvent ||= class ProgressEvent { constructor(type, init = {}) { this.type = type; Object.assign(this, init); } };
const originalTextureLoad = T.TextureLoader.prototype.load;
T.TextureLoader.prototype.load = function (url, onLoad) {
  const texture = new T.Texture(atlas);
  texture.userData.qaAtlas = true;
  texture.needsUpdate = true;
  queueMicrotask(() => onLoad?.(texture));
  return texture;
};
for (const buffer of gltfJson.buffers) {
  const bytes = fs.readFileSync(path.join(path.dirname(modelPath), buffer.uri));
  buffer.uri = `data:application/octet-stream;base64,${bytes.toString('base64')}`;
}
let gltf;
try { gltf = await new GLTFLoader().parseAsync(JSON.stringify(gltfJson), ''); }
finally { T.TextureLoader.prototype.load = originalTextureLoad; }

const html = fs.readFileSync(path.join(repo, 'index.html'), 'utf8');
const start = html.indexOf('const CharacterModels = (() => {');
const end = html.indexOf('\n})();', start) + '\n})();'.length;
assert.ok(start >= 0 && end > start, 'production CharacterModels closure found');
let characterSource = html.slice(start, end);
assert.ok(characterSource.includes('function addAbyssDetails('), 'production Abyss customization found');
characterSource = characterSource.replace('return { create, dispose };',
  'return { create, dispose, _qa: { addAbyssDetails, prepareMaterial } };');
const context = vm.createContext({ THREE: T, World: { renderer: null, MAT: { bomb: null } }, console });
vm.runInContext(characterSource + '\nglobalThis.qaCharacterModels = CharacterModels;', context);
const { _qa: { addAbyssDetails, prepareMaterial }, dispose } = context.qaCharacterModels;
const definitionMatch = html.match(/id:\s*'blue-demon',\s*name:\s*'Abyss',\s*color:\s*(0x[\da-f]+)/i);
assert.ok(definitionMatch, 'actual Abyss fighter definition found');
const definition = { id: 'blue-demon', name: 'Abyss', color: Number(definitionMatch[1]), personality: 'eerie' };
const sourceMesh = gltf.scene.getObjectByName('BlueDemon');
assert.ok(sourceMesh?.isSkinnedMesh, 'actual BlueDemon skinned mesh loaded');
assert.equal(sourceMesh.skeleton.bones.length, 43, 'all original 43 skeleton joints loaded');
assert.equal(gltf.animations.length, 14, 'all original 14 clips loaded');

const fingerprint = () => {
  const hash = createHash('sha256');
  for (const [key, attribute] of Object.entries(sourceMesh.geometry.attributes)) {
    hash.update(key); hash.update(Buffer.from(attribute.array.buffer, attribute.array.byteOffset, attribute.array.byteLength));
  }
  hash.update(Buffer.from(sourceMesh.geometry.index.array.buffer));
  for (const clip of gltf.animations) for (const track of clip.tracks) {
    hash.update(clip.name + track.name);
    hash.update(Buffer.from(track.times.buffer)); hash.update(Buffer.from(track.values.buffer));
  }
  return hash.digest('hex');
};
const originalFingerprint = fingerprint();
const originalMaterials = new Set();
gltf.scene.traverse(object => { if (object.material) (Array.isArray(object.material) ? object.material : [object.material]).forEach(material => originalMaterials.add(material)); });
let sourceGeometryDisposals = 0;
sourceMesh.geometry.addEventListener('dispose', () => sourceGeometryDisposals++);
let sourceTextureDisposals = 0;
sourceMesh.material.map.addEventListener('dispose', () => sourceTextureDisposals++);

function makeModel(customize) {
  const model = clone(gltf.scene);
  const initialMaterials = [];
  model.traverse(object => {
    if (!object.isMesh) return;
    object.userData.sharedModelGeometry = true;
    object.material = Array.isArray(object.material)
      ? object.material.map(material => prepareMaterial(RT, material, definition))
      : prepareMaterial(RT, object.material, definition);
    for (const material of Array.isArray(object.material) ? object.material : [object.material]) initialMaterials.push(material);
  });
  model.updateMatrixWorld(true);
  const bounds = new T.Box3().setFromObject(model);
  const size = bounds.getSize(new T.Vector3());
  model.scale.setScalar(Math.min(0.72 / size.x, 0.95 / size.y, 0.72 / size.z));
  model.updateMatrixWorld(true);
  bounds.setFromObject(model);
  const centre = bounds.getCenter(new T.Vector3());
  model.position.set(-centre.x, -bounds.min.y, -centre.z);
  model.updateMatrixWorld(true);
  if (customize) addAbyssDetails(RT, model);
  model.updateMatrixWorld(true);
  return { model, initialMaterials };
}

function measure(model) {
  let meshes = 0, triangles = 0, lights = 0;
  model.traverseVisible(object => {
    if (object.isLight) lights++;
    if (!object.isMesh) return;
    meshes++;
    triangles += (object.geometry.index?.count ?? object.geometry.attributes.position.count) / 3;
  });
  return { meshes, triangles, lights };
}
function pose(model, name, time) {
  const clip = gltf.animations.find(clip => clip.name === name);
  assert.ok(clip, `pose clip ${name} exists`);
  const mixer = new T.AnimationMixer(model);
  mixer.clipAction(clip).play();
  mixer.setTime(Math.min(Math.max(time, 0), Math.max(0, clip.duration - 0.00001)));
  model.updateMatrixWorld(true);
  model.traverse(object => { if (object.isSkinnedMesh) object.skeleton.update(); });
  return mixer;
}

const baseline = makeModel(false);
const improved = makeModel(true);
const second = makeModel(true);
const face = improved.model.getObjectByName('AbyssFace');
assert.ok(face, 'AbyssFace group exists');
assert.equal(face.parent.name, 'Head', 'face inherits the actual animated Head bone');
const improvedMesh = improved.model.getObjectByName('BlueDemon');
assert.notEqual(improvedMesh.geometry, sourceMesh.geometry, 'recoloured source mesh owns private geometry');
assert.notEqual(improvedMesh.geometry, second.model.getObjectByName('BlueDemon').geometry, 'two instances own independent customised geometry');
for (let joint = 0; joint < sourceMesh.skeleton.bones.length; joint++) {
  assert.notEqual(improvedMesh.skeleton.bones[joint], sourceMesh.skeleton.bones[joint], 'custom instance owns its skeleton bones');
  assert.notEqual(improvedMesh.skeleton.bones[joint], second.model.getObjectByName('BlueDemon').skeleton.bones[joint], 'two instances have independent poses');
}
assert.equal(improvedMesh.userData.sharedModelGeometry, false, 'private customised geometry participates in disposal');
assert.equal(fingerprint(), originalFingerprint, 'cached source geometry and animation tracks remain unchanged');
assert.deepEqual(improvedMesh.geometry.attributes.skinIndex.array, sourceMesh.geometry.attributes.skinIndex.array, 'skin joint indices preserved');
assert.deepEqual(improvedMesh.geometry.attributes.skinWeight.array, sourceMesh.geometry.attributes.skinWeight.array, 'skin weights preserved');
assert.equal(improvedMesh.geometry.attributes.position.count, sourceMesh.geometry.attributes.position.count, 'base topology vertex count preserved');
assert.equal(improvedMesh.geometry.index.count, sourceMesh.geometry.index.count, 'base topology triangle count preserved');

// Customization edits bind-space vertices. Running it after a different live
// head pose or model transform must produce exactly the same owned geometry.
// This catches using Head.matrixWorld.inverse() to edit the source mesh: the
// glTF's default pose is already different from its skin's inverse bind pose.
const posedBeforeCustomization = makeModel(false);
const posedHead = posedBeforeCustomization.model.getObjectByName('Head');
const posedMesh = posedBeforeCustomization.model.getObjectByName('BlueDemon');
const bindHead = posedMesh.skeleton.boneInverses[posedMesh.skeleton.bones.indexOf(posedHead)]
  .clone().multiply(posedMesh.bindMatrix);
const defaultPoseHead = posedHead.matrixWorld.clone().invert().multiply(posedMesh.matrixWorld);
assert.ok(bindHead.elements.some((value, index) => Math.abs(value - defaultPoseHead.elements[index]) > 0.01),
  'fixture actually distinguishes bind coordinates from the glTF default posed coordinates');
posedHead.rotateX(-0.33);
posedHead.rotateY(0.67);
posedBeforeCustomization.model.position.add(new T.Vector3(0.17, -0.08, 0.23));
posedBeforeCustomization.model.scale.multiplyScalar(1.4);
posedBeforeCustomization.model.updateMatrixWorld(true);
addAbyssDetails(RT, posedBeforeCustomization.model);
for (const attribute of ['position', 'normal', 'color']) {
  assert.deepEqual(posedMesh.geometry.getAttribute(attribute).array, improvedMesh.geometry.getAttribute(attribute).array,
    `${attribute}: customization is independent of current head pose and model transform`);
}
const posedFace = posedBeforeCustomization.model.getObjectByName('AbyssFace');
for (const expected of face.children) {
  const actual = posedFace.getObjectByName(expected.name);
  assert.deepEqual(actual.geometry.getAttribute('position').array, expected.geometry.getAttribute('position').array,
    `${expected.name}: facial overlays retain their head-local coordinates in another pose`);
}
dispose(posedBeforeCustomization.model);

const beforeCounts = measure(baseline.model), afterCounts = measure(improved.model);
assert.equal(afterCounts.lights, 0, 'face glow adds no real-time lights');
assert.ok(afterCounts.meshes <= beforeCounts.meshes + 6, 'custom face adds at most six batched meshes');
assert.ok(afterCounts.triangles <= beforeCounts.triangles + 6000, 'face stays within the additional 6000-triangle budget');
const firstMaterials = new Set(), secondMaterials = new Set();
for (const [root, set] of [[improved.model, firstMaterials], [second.model, secondMaterials]]) root.traverse(object => {
  if (object.material) (Array.isArray(object.material) ? object.material : [object.material]).forEach(material => set.add(material));
});
for (const material of firstMaterials) {
  assert.ok(!originalMaterials.has(material), 'custom materials do not alias source material');
  assert.ok(!secondMaterials.has(material), 'custom materials are independent between instances');
}

const sampledClips = [];
for (const clip of gltf.animations) {
  const sample = makeModel(true);
  const mixer = new T.AnimationMixer(sample.model);
  mixer.clipAction(clip).play();
  const vertex = new T.Vector3();
  const sampleTimes = [0, clip.duration * 0.5, Math.max(0, clip.duration - 0.001)];
  for (const time of sampleTimes) {
    mixer.setTime(time);
    sample.model.updateMatrixWorld(true);
    sample.model.traverseVisible(object => {
      if (!object.isMesh) return;
      if (object.isSkinnedMesh) object.skeleton.update();
      const positions = object.geometry.getAttribute('position');
      for (let i = 0; i < positions.count; i++) {
        object.getVertexPosition(i, vertex).applyMatrix4(object.matrixWorld);
        assert.ok(Number.isFinite(vertex.x) && Number.isFinite(vertex.y) && Number.isFinite(vertex.z), `${clip.name}: posed vertices finite`);
        assert.ok(vertex.length() < 10, `${clip.name}: no exploded skin geometry`);
      }
    });
    const sampleFace = sample.model.getObjectByName('AbyssFace');
    assert.equal(sampleFace.parent.name, 'Head', `${clip.name}: facial attachment maintained`);
  }
  sampledClips.push({ name: clip.name, duration: clip.duration, samples: sampleTimes.length });
  mixer.stopAllAction(); mixer.uncacheRoot(sample.model);
  dispose(sample.model);
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
      if (material.map && uv) {
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
    });
  });
  return { bounds: { min: bounds.min.toArray(), max: bounds.max.toArray() }, counts: measure(model), meshes };
}
const beforeMixer = pose(baseline.model, poseName, poseTime);
const afterMixer = pose(improved.model, poseName, poseTime);
const geometryExport = {
  schema: 'abyss-posed-geometry-v1',
  metadata: { clip: poseName, time: poseTime, colourSpace: 'linear-sRGB', coordinates: 'world-space; +Y up; +Z front', sourceFingerprint: originalFingerprint },
  variants: { before: exportVariant(baseline.model), after: exportVariant(improved.model) },
};
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify(geometryExport));

const disposalMaterials = new Set([...firstMaterials, ...secondMaterials]);
const disposalGeometries = new Set();
for (const root of [improved.model, second.model]) root.traverse(object => {
  if (object.geometry && !object.userData.sharedModelGeometry) disposalGeometries.add(object.geometry);
});
const disposalCounts = new Map();
for (const resource of [...disposalMaterials, ...disposalGeometries]) {
  disposalCounts.set(resource, 0);
  resource.addEventListener('dispose', () => disposalCounts.set(resource, disposalCounts.get(resource) + 1));
}
beforeMixer.stopAllAction(); beforeMixer.uncacheRoot(baseline.model);
afterMixer.stopAllAction(); afterMixer.uncacheRoot(improved.model);
dispose(baseline.model); dispose(improved.model); dispose(second.model);
dispose(improved.model); // disposal must remain idempotent
for (const [resource, count] of disposalCounts) assert.equal(count, 1, `${resource.type}: custom instance resource disposed exactly once`);
assert.equal(sourceGeometryDisposals, 0, 'cached source geometry survived all instance disposal');
assert.equal(sourceTextureDisposals, 0, 'cached atlas survived all instance disposal');
assert.equal(fingerprint(), originalFingerprint, 'source and all animation clips intact after repeated create/pose/dispose');

console.log(JSON.stringify({
  status: 'PASS', checkScope: 'real local Three.js CPU geometry, skeleton, materials and animation; no GPU/device FPS claim',
  original: beforeCounts, improved: afterCounts,
  joints: sourceMesh.skeleton.bones.length, clips: sampledClips,
  animationPoseSamples: sampledClips.reduce((sum, clip) => sum + clip.samples, 0),
  ownershipAndDisposal: 'passed', bindCoordinatePoseInvariance: 'passed', output,
}));
