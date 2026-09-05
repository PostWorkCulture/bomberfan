import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(process.argv[2] || path.join(path.dirname(fileURLToPath(import.meta.url)), '..'));
const html = fs.readFileSync(path.join(repo, 'index.html'), 'utf8');
const fighters = [...html.matchAll(/model:\s*'([^']+)',\s*portrait:\s*'([^']+)'/g)]
  .map(([, model, portrait]) => ({ model, portrait }));

assert.equal(fighters.length, 20, 'all 20 fighter definitions are present');
assert.equal(new Set(fighters.map(fighter => fighter.model)).size, 20, 'fighter model paths are unique');
assert.equal(new Set(fighters.map(fighter => fighter.portrait)).size, 20, 'fighter portrait paths are unique');

let animations = 0;
for (const fighter of fighters) {
  const modelPath = path.join(repo, fighter.model);
  const portraitPath = path.join(repo, fighter.portrait);
  assert.ok(fs.statSync(portraitPath).size > 0, `${fighter.portrait} is present`);

  const gltf = JSON.parse(fs.readFileSync(modelPath, 'utf8'));
  assert.equal(gltf.asset?.version, '2.0', `${fighter.model} is glTF 2.0`);
  assert.ok(gltf.meshes?.length > 0, `${fighter.model} contains meshes`);
  assert.ok(gltf.skins?.length > 0, `${fighter.model} contains a skin`);
  assert.ok(gltf.animations?.length >= 8, `${fighter.model} contains the required animation set`);
  animations += gltf.animations.length;

  for (const resource of [...(gltf.buffers || []), ...(gltf.images || [])]) {
    assert.ok(resource.uri && !/^(?:data:|https?:|\/)/.test(resource.uri), `${fighter.model} uses a local resource URI`);
    const resourcePath = path.resolve(path.dirname(modelPath), resource.uri);
    assert.ok(resourcePath.startsWith(path.dirname(modelPath) + path.sep), `${fighter.model} resource stays inside its asset directory`);
    assert.ok(fs.statSync(resourcePath).size > 0, `${fighter.model} resource ${resource.uri} is present`);
  }
}

for (const file of [
  'assets/vendor/character-bootstrap.js',
  'assets/vendor/three.module.min.js',
  'assets/vendor/three.core.min.js',
  'assets/vendor/GLTFLoader.js',
  'assets/vendor/SkeletonUtils.js',
  'assets/vendor/BufferGeometryUtils.js',
  'manifest.webmanifest',
  'icon-192.png',
  'icon-512.png',
  'icon-maskable.png',
  'apple-touch-icon.png',
]) assert.ok(fs.statSync(path.join(repo, file)).size > 0, `${file} is present`);

console.log(`PASS assets: ${fighters.length} fighter models, ${fighters.length} portraits, ${animations} animation clips and all runtime/PWA files are present.`);
