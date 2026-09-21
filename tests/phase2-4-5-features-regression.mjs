import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(scriptDir, '..');

const html = fs.readFileSync(path.join(repo, 'index.html'), 'utf8');
const source = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes('const Game ='));
assert.ok(source, 'embedded game script found');

// 1. Phase 2: Volcano Arena & Hazards
assert.ok(source.includes("id: 'volcano', name: 'Volcano'"), 'Volcano level definition present in LEVELS');
assert.ok(source.includes("magma_spire(g)"), 'magma_spire prop builder present in Props.BUILD');
assert.ok(source.includes("vent(g)"), 'vent prop builder present in Props.BUILD');
assert.ok(source.includes("geyser(g, angry)"), 'geyser hazard builder present in Props.BUILD');
assert.ok(fs.existsSync(path.join(repo, 'assets/lighting/volcano-ao.png')), 'volcano-ao.png exists');
assert.ok(fs.existsSync(path.join(repo, 'assets/lighting/volcano-bounce.png')), 'volcano-bounce.png exists');

const layouts = JSON.parse(fs.readFileSync(path.join(repo, 'assets/lighting/layouts.json'), 'utf8'));
assert.ok(layouts.volcano, 'volcano layout exists in layouts.json');

// 2. Phase 4: Visuals, VFX & Audio Polish (white ground shockwave removed)
assert.ok(!source.includes("this.shock = new THREE.Mesh"), 'Blast shock mesh cleanly removed');
assert.ok(!source.includes("this.shockOuter = new THREE.Mesh"), 'Blast shockOuter mesh cleanly removed');
assert.ok(source.includes("function updateEmbers(dt)"), 'Volcano atmospheric updateEmbers defined');
assert.ok(source.includes("updateEmbers(dt);"), 'updateEmbers called in simulation loop');
assert.ok(source.includes("suddenDeath(c, o, t)"), 'Audio3.SFX.suddenDeath defined');
assert.ok(source.includes("suddenDeath(){ play('suddenDeath'); }"), 'Audio3.suddenDeath exported');
assert.ok(source.includes("Audio3.suddenDeath();"), 'startSuddenDeath calls Audio3.suddenDeath');
assert.ok(source.includes("volcano: { root: 32.70"), 'Volcano deep bassline defined in Audio3.BASS');

// 3. Phase 5: Quality-of-Life, UI & Settings
assert.ok(source.includes("ROUND_OPTIONS = [1, 2, 3, 5]"), 'ROUND_OPTIONS includes 5 for longer matches');
assert.ok(source.includes("const SFX_STEPS = ["), 'SFX_STEPS defined in Audio3');
assert.ok(source.includes("setSfxStep,"), 'setSfxStep exported from Audio3');
assert.ok(source.includes("cycleSfx(delta)"), 'cycleSfx exported from Audio3');
assert.ok(html.includes('class="pmusic psfx" data-act="sfx"'), 'SFX volume row present in pause panel');
assert.ok(source.includes("btn.dataset.act.startsWith('sfx')"), 'bindPause handles SFX volume buttons');

// 4. Forest Realism & Pause Menu Pickup Guide
assert.ok(source.includes("needlesBase"), 'realistic tiered needles present in Props.BUILD.pine');
assert.ok(source.includes("volva"), 'organic bulbous volva present in Props.BUILD.toadstool');
assert.ok(source.includes("gills"), 'underside radial gills present in Props.BUILD.toadstool');
assert.ok(html.includes('data-act="guide" class="pbtn-guide"'), 'Pickup Guide button present in pause panel');
assert.ok(html.includes('class="panel pause-guide hidden"'), 'Pickup Guide modal present in pause menu');
assert.ok(html.includes('Bomb Up'), 'Bomb Up pickup listed in Pickup Guide');
assert.ok(html.includes('Power Glove'), 'Power Glove pickup listed in Pickup Guide');
assert.ok(html.includes('Remote Detonator'), 'Remote Detonator pickup listed in Pickup Guide');
assert.ok(html.includes('Curse / Skull'), 'Curse / Skull listed in Pickup Guide');
assert.ok(source.includes("guide() {"), 'guide action handler present in bindPause');
assert.ok(source.includes("guideclose() {"), 'guideclose action handler present in bindPause');

console.log('PASS Phase 2, 4 & 5 (Volcano Arena, VFX/Audio Polish, Forest Realism, Pickup Guide & Settings) integration verified.');
