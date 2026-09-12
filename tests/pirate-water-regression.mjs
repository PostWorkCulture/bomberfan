import assert from 'node:assert/strict';
import * as T from '../assets/vendor/three.module.min.js';
import {createPirateWater} from '../assets/vendor/pirate-water.js';
const material=createPirateWater();
assert.ok(material.isMeshPhysicalMaterial);assert.equal(material.ior,1.333);assert.equal(material.clearcoat,1);
const shader={uniforms:{},vertexShader:T.ShaderLib.physical.vertexShader,fragmentShader:T.ShaderLib.physical.fragmentShader};
material.onBeforeCompile(shader);
assert.equal(shader.uniforms.waterTime,material.userData.waterTime);
assert.ok(shader.vertexShader.includes('transformed.z+=waveField'));
assert.ok(shader.fragmentShader.includes('clearcoatNormal=normal;'));
assert.ok(shader.fragmentShader.includes('diffuseColor.rgb+='));
assert.ok(shader.fragmentShader.includes('#include <tonemapping_fragment>'));
for(const text of [shader.vertexShader,shader.fragmentShader]){
 assert.equal([...text].filter(c=>c==='{').length,[...text].filter(c=>c==='}').length);
 assert.equal((text.match(/uniform float waterTime;/g)||[]).length,1);
}
material.userData.waterTime.value=12;assert.equal(shader.uniforms.waterTime.value,12);
material.dispose();
console.log('PASS water material: wave/normal/clearcoat shader hooks, shared clock, physical optics and retained tone mapping. GPU shader compilation remains unverified.');
