// Node-only regression checks. No browser or GPU performance is measured.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const parentDir = path.resolve(scriptDir, '..');
const inferredRepo = fs.existsSync(path.join(parentDir, 'index.html')) ? parentDir : path.join(parentDir, 'bomberfan');
const repo = path.resolve(process.argv[2] || inferredRepo);
const qaProfile = process.env.BF_QA_PROFILE || 'desktop';
const qaWidth = Number(process.env.BF_QA_WIDTH || 1280);
const qaHeight = Number(process.env.BF_QA_HEIGHT || 720);
const qaDpr = Number(process.env.BF_QA_DPR || 1);
const qaTouch = process.env.BF_QA_TOUCH === '1';
const qaCoarse = process.env.BF_QA_COARSE === undefined ? qaTouch : process.env.BF_QA_COARSE === '1';
const qaFine = process.env.BF_QA_FINE === undefined ? !qaTouch : process.env.BF_QA_FINE === '1';
const qaQuiet = process.env.BF_QA_QUIET === '1';
const modules = process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES || '/opt/codex/runtimes/codex-primary-runtime/dependencies/node/node_modules';
const require = createRequire(path.join(modules, 'package.json'));
const { createCanvas } = require('@napi-rs/canvas');
const ThreeModule = await import(pathToFileURL(path.join(repo, 'assets/vendor/three.module.min.js')));
const noop = () => {};
const events = new Map();
const listen = (name, fn) => { if (!events.has(name)) events.set(name, []); events.get(name).push(fn); };
const dispatch = name => (events.get(name) || []).forEach(fn => fn({ type: name, preventDefault: noop }));
function element() {
  return {
    style: { setProperty: noop, removeProperty: noop }, dataset: {},
    classList: { add: noop, remove: noop, toggle: noop, contains: () => false },
    addEventListener: listen, removeEventListener: noop,
    appendChild: noop, remove: noop, setAttribute: noop, removeAttribute: noop,
    getBoundingClientRect: () => ({ x: 0, y: 0, left: 0, top: 0, right: qaWidth, bottom: qaHeight, width: qaWidth, height: qaHeight }),
    querySelector: () => null, querySelectorAll: () => [],
    width: qaWidth, height: qaHeight, clientWidth: qaWidth, clientHeight: qaHeight,
  };
}
const canvas = Object.assign(createCanvas(qaWidth, qaHeight), element());
class StubRenderer {
  constructor(opts) {
    this.domElement = opts.canvas || canvas;
    this.shadowMap = {}; this.info = { render: { calls: 0 }, memory: { geometries: 0, textures: 0 }, programs: [] };
    this.capabilities = { isWebGL2: true, getMaxAnisotropy: () => 4 };
    this.ratio = 1;
  }
  setPixelRatio(v) { this.ratio = v; }
  getPixelRatio() { return this.ratio; }
  setSize(w, h) { this.domElement.width = w; this.domElement.height = h; }
  getSize(target) { return target.set(this.domElement.clientWidth, this.domElement.clientHeight); }
  getDrawingBufferSize(target) { return target.set(this.domElement.width * this.ratio, this.domElement.height * this.ratio); }
  setScissorTest() {} setViewport() {} setScissor() {} clear() {} clearDepth() {} dispose() {}
  render() { this.info.render.calls++; }
  compileAsync() { return Promise.resolve(); }
}
const document = {
  body: element(), documentElement: element(), hidden: false, visibilityState: 'visible',
  fonts: { ready: Promise.resolve(), check: () => true },
  addEventListener: listen, removeEventListener: noop,
  querySelector: () => null, querySelectorAll: () => [],
  getElementById: id => id === 'scene' ? canvas : null,
  createElement: tag => tag === 'canvas' ? Object.assign(createCanvas(128, 128), element()) : element(),
};
const storage = new Map();
const context = vm.createContext({
  console, THREE: { ...ThreeModule, WebGLRenderer: StubRenderer }, document,
  navigator: { userAgent: `Bomberfan ${qaProfile} regression`, hardwareConcurrency: 8, maxTouchPoints: qaCoarse ? 5 : 0 },
  location: { search: '', href: 'https://example.test/' }, URLSearchParams, URL,
  performance: { now: () => 0 },
  setTimeout: () => 0, clearTimeout: noop, setInterval: () => 0, clearInterval: noop,
  requestAnimationFrame: () => 1, cancelAnimationFrame: noop,
  innerWidth: qaWidth, innerHeight: qaHeight, devicePixelRatio: qaDpr,
  matchMedia: query => ({
    matches: query.includes('(pointer: coarse)') ? qaCoarse
      : query.includes('(any-pointer: fine)') ? qaFine
      : query.includes('(prefers-reduced-motion: reduce)') ? false : false,
    addEventListener: noop, removeEventListener: noop,
  }),
  getComputedStyle: () => ({ getPropertyValue: () => '', display: 'block' }),
  addEventListener: listen, removeEventListener: noop,
  localStorage: { getItem: k => storage.get(k) ?? null, setItem: (k, v) => storage.set(k, String(v)), removeItem: k => storage.delete(k) },
});
context.window = context; context.self = context;
const html = fs.readFileSync(path.join(repo, 'index.html'), 'utf8');
const source = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes('const Game ='));
assert.ok(source, 'embedded game script found');
const exportMarker = '    init, tryPlaceBomb, tryAction, tryKick, spawnPuff';
assert.ok(source.includes(exportMarker), 'test-only internal export insertion point found');
const instrumented = source
  .replace(/^import .*;$/m, '')
  .replace(exportMarker, '    _qa: { tick, frame, startRound, clearRoundEntities, startMatch, toMenu },\n' + exportMarker);
vm.runInContext(instrumented, context, { filename: path.join(repo, 'index.html:embedded-game') });
const { Game, World, Input, UI, TouchPad, Audio3, Player, Bomb, Blast, PowerUp, AI, CFG, CELL, STATE, KEYMAPS, LEVELS, PU } = context.BlastArena;
const touchElements = new Map(['touch', 'tzone', 'tbombzone', 'tspecialzone', 'tspecial', 'tstick', 'tknob', 'tbomb'].map(id => [id, element()]));
document.getElementById = id => id === 'scene' ? canvas : (touchElements.get(id) || null);
TouchPad.init();
const platformState = {
  touchFirst: TouchPad.available,
  controlsActive: TouchPad.active,
  compact: UI.isCompact(),
  orientationBlocked: UI.isBlockedByOrientation(),
};
const manualPreference = qaTouch ? 'off' : 'on';
TouchPad.setPref(manualPreference);
platformState.manualPreference = TouchPad.pref;
platformState.manualControlsActive = TouchPad.active;
TouchPad._reset();
platformState.resetControlsActive = TouchPad.active;
// DOM layout, audio devices and asynchronously loaded character rigs are outside
// this harness. Actual simulation, scene objects, arena geometry, bombs, blasts,
// power-ups, collision and AI remain the production implementation.
for (const target of [UI, TouchPad, Audio3]) {
  for (const key of Object.keys(target)) {
    const d = Object.getOwnPropertyDescriptor(target, key);
    if (d.writable && typeof target[key] === 'function') target[key] = noop;
  }
}
UI.rowVisible = () => true; UI.isBlockedByOrientation = () => false;
UI.isCompact = () => platformState.compact; UI.isPadded = () => false;
UI.hudBlockRects = () => []; UI.viewportH = () => qaHeight;
Player.buildMesh = () => new ThreeModule.Group();
Game.init(canvas);
const results = [];
const crateMetrics = [];
function check(name, fn) {
  fn(); results.push({ name, passed: true }); if (!qaQuiet) console.log('PASS ' + name);
}
const g = Game._debug;
const releaseInputs = () => { KEYMAPS.forEach(km => Object.values(km).flat().forEach(k => Input.release(k))); Input.clearPresses(); };
function start() {
  releaseInputs();
  g.opts.humans = 2; g.opts.wins = 2; g.opts.level = LEVELS[0].id;
  Game._qa.startMatch();
  // Keep all seats controllable and stationary while isolating physics checks.
  g.players.forEach(p => { p.ai = null; p.isHuman = true; p.keymap = null; });
  g.players[0].keymap = KEYMAPS[1];
  Game.advance(CFG.ROUND_INTRO + CFG.FIXED_DT);
  assert.equal(Game.state, STATE.PLAY);
  return g.players[0];
}
function put(p, x, y) { World.setCell(x, y, CELL.EMPTY); p.gx = x; p.gy = y; p.syncMesh(); }
function corridor(y, from = 1, to = CFG.COLS - 2) { for (let x = from; x <= to; x++) World.setCell(x, y, CELL.EMPTY); }
function tick(n = 1) { Game.advance(n * CFG.FIXED_DT); }

check('platform profile selects the correct input/layout mode and drawing budget', () => {
  assert.equal(platformState.touchFirst, qaTouch);
  assert.equal(platformState.controlsActive, qaTouch);
  assert.equal(platformState.manualPreference, manualPreference);
  assert.equal(platformState.manualControlsActive, !qaTouch);
  assert.equal(platformState.resetControlsActive, qaTouch);
  assert.equal(platformState.compact, qaTouch || qaHeight <= 560 || qaWidth <= 820);
  assert.equal(platformState.orientationBlocked, qaTouch && qaHeight > qaWidth);
  assert.ok(Math.abs(World.camera.aspect - qaWidth / qaHeight) < 1e-10);
  const ratio = World.performance.pixelRatio;
  assert.ok(ratio <= Math.min(qaDpr, 1.5));
  assert.ok(qaWidth * qaHeight * ratio * ratio <= 2000000 + 1);
});

check('match starts after the countdown with four alive players', () => {
  start(); assert.equal(g.players.length, 4); assert.ok(g.players.every(p => p.alive));
});

check('substep render frames preserve a bomb tap until simulation consumes it once', () => {
  const p = start(); put(p, 5, 5); corridor(5); p.maxBombs = 4;
  Game._qa.frame(1000);
  Input.press(KEYMAPS[1].action[0]); Input.release(KEYMAPS[1].action[0]);
  Game._qa.frame(1004); assert.equal(Game.bombs.length, 0);
  Game._qa.frame(1008); assert.equal(Game.bombs.length, 0);
  Game._qa.frame(1018); assert.equal(Game.bombs.length, 1);
  put(p, 6, 5); tick(3); assert.equal(Game.bombs.length, 1);
});

check('fixed simulation steps move at configured speed and stop at a wall', () => {
  const p = start(); corridor(5); put(p, 5, 5);
  Input.press(KEYMAPS[1].right); tick(10);
  assert.ok(Math.abs(p.gx - (5 + CFG.BASE_SPEED * CFG.FIXED_DT * 10)) < 1e-8);
  World.setCell(7, 5, CELL.HARD); tick(90); Input.release(KEYMAPS[1].right);
  assert.ok(p.gx < 6.5 - CFG.PLAYER_RADIUS + 0.001);
  assert.ok(!p.blockedAt(p.gx, p.gy));
  assert.ok(p.gx > 6, 'player approached rather than stopping a tile away');
});

check('held direction prioritises the latest press and releases on window blur', () => {
  releaseInputs(); Input.press(KEYMAPS[1].left); Input.press(KEYMAPS[1].up);
  assert.equal(Input.direction(KEYMAPS[1]).y, -1);
  Input.release(KEYMAPS[1].up); assert.equal(Input.direction(KEYMAPS[1]).x, -1);
  dispatch('blur'); assert.equal(Input.direction(KEYMAPS[1]).x, 0); releaseInputs();
});

check('a placed bomb can be exited but blocks re-entry and obeys capacity', () => {
  const p = start(); corridor(5); put(p, 5, 5); p.maxBombs = 1;
  assert.ok(Game.tryPlaceBomb(p)); assert.equal(p.activeBombs, 1);
  assert.equal(Game.tryPlaceBomb(p), false);
  Input.press(KEYMAPS[1].right); tick(16); Input.release(KEYMAPS[1].right);
  assert.ok(p.gx > 5.8); assert.equal(p.ignoreBombs.size, 0);
  Input.press(KEYMAPS[1].left); tick(12); Input.release(KEYMAPS[1].left);
  assert.ok(p.gx >= 5.5 + CFG.PLAYER_RADIUS - 0.01);
  assert.equal(Game.bombAt(World.key(5, 5)), Game.bombs[0]);
});

check('adjacent bombs chain, honour hard walls, damage players and clear expired entities', () => {
  const p = start(); corridor(5); p.maxBombs = 3; p.fire = 3;
  put(p, 5, 5); assert.ok(Game.tryPlaceBomb(p));
  put(p, 7, 5); assert.ok(Game.tryPlaceBomb(p));
  const bombs = [...Game.bombs]; const roots = bombs.map(b => b.mesh);
  put(p, 3, 7); put(g.players[1], 8, 5); put(g.players[2], 11, 9); put(g.players[3], 13, 11);
  World.setCell(9, 5, CELL.HARD);
  bombs[0].fuse = CFG.FIXED_DT / 2; bombs[1].fuse = 10;
  tick(2);
  assert.ok(bombs.every(b => b.dead)); assert.equal(p.activeBombs, 0);
  assert.equal(Game.bombs.length, 0); assert.equal(g.bombMap.size, 0);
  assert.ok(roots.every(root => root.parent === null));
  assert.equal(Game.blasts.length, 1); const blast = Game.blasts[0];
  assert.ok(blast.tiles.has('8,5')); assert.ok(!blast.tiles.has('9,5')); assert.ok(!blast.tiles.has('10,5'));
  assert.equal(g.players[1].alive, false);
  let materialDisposals = 0;
  [blast.matArm, blast.matCore, blast.matShock].forEach(m => m.addEventListener('dispose', () => materialDisposals++));
  Game.advance(CFG.BLAST_LIFE + 0.1);
  assert.equal(Game.blasts.length, 0); assert.equal(blast.group.parent, null); assert.equal(materialDisposals, 3);
});

check('power-up pickup modifies the player and removes its scene entity', () => {
  const p = start(); put(p, 5, 5); Game.spawnPowerUp(5, 5, PU.BOMB);
  const item = Game.powerUps.get('5,5'); const before = p.maxBombs;
  tick(); assert.equal(p.maxBombs, before + 1); assert.equal(Game.powerUps.has('5,5'), false); assert.equal(item.mesh.parent, null);
});

check('a draw advances to a clean new round with reset players', () => {
  const p = start(); corridor(5); put(p, 5, 5); Game.tryPlaceBomb(p);
  Game.spawnPowerUp(6, 5, PU.FIRE);
  const roots = [...Game.bombs.map(b => b.mesh), ...Game.powerUps.values()].map(v => v.mesh || v);
  const round = g.round; Game.endRound(null); Game.advance(3.1);
  assert.equal(g.round, round + 1); assert.equal(Game.state, STATE.INTRO);
  assert.equal(Game.bombs.length, 0); assert.equal(Game.blasts.length, 0); assert.equal(Game.powerUps.size, 0);
  assert.equal(g.bombMap.size, 0); assert.ok(roots.every(root => root.parent === null));
  assert.ok(g.players.every(player => player.alive && player.activeBombs === 0 && player.fire === CFG.START_FIRE));
  Game.advance(CFG.ROUND_INTRO); assert.equal(Game.state, STATE.PLAY);
});

check('hiding the page pauses simulation, discards queued actions and prevents catch-up on return', () => {
  start(); Game._qa.frame(2000);
  Input.press(KEYMAPS[1].action[0]); Input.release(KEYMAPS[1].action[0]);
  document.hidden = true; document.visibilityState = 'hidden'; dispatch('visibilitychange');
  assert.equal(g.paused, true); const before = Game.roundTime;
  Game._qa.frame(20000); assert.equal(Game.roundTime, before);
  document.hidden = false; document.visibilityState = 'visible'; dispatch('visibilitychange');
  Game._qa.frame(40000); assert.equal(Game.roundTime, before); assert.equal(g.paused, true);
  Input.press('Escape'); Input.release('Escape'); assert.equal(g.paused, false);
  Game._qa.frame(40018); assert.ok(before - Game.roundTime <= CFG.FIXED_DT * 1.1);
  assert.equal(Game.bombs.length, 0, 'bomb queued before hiding does not fire on return');
});

check('more simultaneous blasts than available lights update and release the fixed pool safely', () => {
  start(); const pointLights = () => { let count = 0; World.scene.traverse(o => { if (o.isPointLight) count++; }); return count; };
  const baselineLights = pointLights();
  const sharedGeometry = Object.values(Blast.geometry);
  let geometryDisposals = 0;
  sharedGeometry.forEach(geometry => geometry.addEventListener('dispose', () => geometryDisposals++));
  const blasts = Array.from({ length: 9 }, (_, i) => new Blast([
    { x: i + 2, y: 5, kind: 'core' }, { x: i + 2, y: 6, kind: 'arm' },
  ]));
  assert.equal(pointLights(), baselineLights, 'explosions do not change the scene light count');
  blasts.forEach(b => b.group.traverse(o => { if (o.isMesh) assert.ok(sharedGeometry.includes(o.geometry)); }));
  const allocated = blasts.filter(b => b.light).map(b => b.light);
  assert.equal(allocated.length, 4); assert.equal(new Set(allocated).size, 4);
  blasts.forEach(b => { b.rainbow = true; b.update(CFG.FIXED_DT); b.dispose(); b.dispose(); });
  assert.ok(allocated.every(light => light.intensity === 0));
  assert.equal(pointLights(), baselineLights); assert.equal(geometryDisposals, 0);
  const next = new Blast([{ x: 5, y: 5, kind: 'core' }]);
  assert.ok(allocated.includes(next.light), 'released lights can be reused'); next.dispose();
  assert.equal(geometryDisposals, 0);
});

check('normal, mine and remote bombs dispose owned resources exactly once and preserve shared shell materials', () => {
  const p = start();
  for (const variant of ['normal', 'mine', 'remote', 'custom-shell']) {
    p.mine = variant === 'mine'; p.remote = variant === 'remote';
    p.shellMat = variant === 'custom-shell' ? new ThreeModule.MeshStandardMaterial({ color: 0xee2222 }) : null;
    const bomb = new Bomb(5, 5, p); const shared = p.shellMat || World.MAT.bomb;
    const owned = new Set(); let sharedDisposals = 0;
    shared.addEventListener('dispose', () => sharedDisposals++);
    bomb.mesh.traverse(o => {
      if (o.geometry) owned.add(o.geometry);
      if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach(m => { if (m !== shared) owned.add(m); });
    });
    const disposalCounts = new Map();
    owned.forEach(resource => {
      disposalCounts.set(resource, 0);
      resource.addEventListener('dispose', () => disposalCounts.set(resource, disposalCounts.get(resource) + 1));
    });
    // Add a second user of the same geometry/material to prove deduplication.
    const original = bomb.mesh.children.find(o => o.isMesh);
    bomb.mesh.add(new ThreeModule.Mesh(original.geometry, original.material));
    bomb.dispose(); bomb.dispose();
    assert.equal(bomb.mesh.parent, null); assert.equal(sharedDisposals, 0, variant);
    assert.ok(owned.size > 0); assert.ok([...disposalCounts.values()].every(n => n === 1), variant);
    if (p.shellMat) p.shellMat.dispose();
  }
  p.mine = p.remote = false; p.shellMat = null;
});

check('crate instance zero and final crate collapse; arena rebuild disposes previous instance buffers', () => {
  start();
  const crates = World.group.getObjectByName('ArenaCrates'); assert.ok(crates?.isInstancedMesh);
  const cells = [];
  for (let y = 0; y < CFG.ROWS; y++) for (let x = 0; x < CFG.COLS; x++) if (World.cellAt(x, y) === CELL.SOFT) cells.push([x, y]);
  assert.equal(cells.length, crates.count); assert.ok(cells.length > 1);
  const matrix = new ThreeModule.Matrix4(); const first = cells[0];
  crates.getMatrixAt(0, matrix);
  assert.ok(Math.abs(matrix.elements[12] - World.wx(first[0])) < 1e-7);
  assert.ok(Math.abs(matrix.elements[14] - World.wz(first[1])) < 1e-7);
  const hidden = World._hidden().get(World.key(...first)) || null;
  const version = crates.instanceMatrix.version;
  assert.equal(World.destroySoft(...first), hidden); assert.equal(World.cellAt(...first), CELL.EMPTY);
  crates.getMatrixAt(0, matrix); assert.equal(matrix.determinant(), 0);
  assert.ok(crates.instanceMatrix.version > version); assert.equal(World.destroySoft(...first), null);
  cells.slice(1).forEach(cell => World.destroySoft(...cell));
  assert.equal(World.softCount(), 0); crates.getMatrixAt(crates.count - 1, matrix); assert.equal(matrix.determinant(), 0);
  const instances = []; World.group.traverse(o => { if (o.isInstancedMesh) instances.push(o); });
  const counts = new Map(); instances.forEach(instance => {
    counts.set(instance, 0); instance.addEventListener('dispose', () => counts.set(instance, counts.get(instance) + 1));
  });
  let sharedMaterialDisposals = 0; World.MAT.soft.addEventListener('dispose', () => sharedMaterialDisposals++);
  Game._qa.startRound();
  assert.ok([...counts.values()].every(n => n === 1), 'each old instance dispatches its buffer-disposal event once');
  assert.ok(instances.every(o => o.parent === null)); assert.equal(sharedMaterialDisposals, 0);
  assert.ok(World.softCount() > 0); assert.notEqual(World.group.getObjectByName('ArenaCrates'), crates);
});

check('last surviving player wins once, reaches match end and returns to the menu cleanly', () => {
  const p = start(); g.opts.wins = 1; const oldPlayers = [...g.players];
  oldPlayers.slice(1).forEach(player => player.kill(true));
  Game.advance(0.75); assert.equal(Game.state, STATE.ROUND_END); assert.equal(p.wins, 1); assert.equal(g.roundWinner, p);
  assert.ok(g.victory?.scene); Game.advance(CFG.ROUND_OUTRO + 0.1);
  assert.equal(Game.state, STATE.MATCH_END); assert.equal(p.wins, 1);
  Game._qa.toMenu(); assert.equal(Game.state, STATE.MENU); assert.equal(Game.players.length, 0);
  assert.equal(g.victory, null); assert.ok(oldPlayers.every(player => player.mesh.parent === null));
});

check('adaptive resolution reduces sustained slow-frame load without changing simulation and obeys the pixel ceiling', () => {
  const p = start(); put(p, 5, 5); corridor(5);
  context.innerWidth = 1920; context.innerHeight = 1080; context.devicePixelRatio = 3;
  World.renderer.setPixelRatio(1.5); World.resize();
  const initial = World.performance.pixelRatio; const beforeTime = Game.roundTime; const beforeX = p.gx;
  for (let i = 0; i < 100; i++) World.adaptResolution(1 / 30, true);
  assert.ok(World.performance.pixelRatio < initial); assert.ok(World.performance.averageMs > 22);
  assert.equal(Game.roundTime, beforeTime); assert.equal(p.gx, beforeX);
  Input.press(KEYMAPS[1].right); tick(10); Input.release(KEYMAPS[1].right);
  assert.ok(Math.abs(p.gx - (beforeX + CFG.BASE_SPEED * CFG.FIXED_DT * 10)) < 1e-8);
  const reduced = World.performance.pixelRatio;
  for (let i = 0; i < 100; i++) World.adaptResolution(1 / 30, false);
  assert.equal(World.performance.pixelRatio, reduced, 'paused samples do not reduce resolution');
  for (let i = 0; i < 800; i++) World.adaptResolution(1 / 60, true);
  assert.ok(World.performance.pixelRatio > reduced, 'sustained smooth samples allow cautious recovery');
  for (const [width, height] of [[1920, 1080], [2560, 1440], [3840, 2160]]) {
    context.innerWidth = width; context.innerHeight = height; World.renderer.setPixelRatio(1.5); World.resize();
    const ratio = World.performance.pixelRatio;
    assert.ok(width * height * ratio * ratio <= 2000000 + 1, `${width}x${height} exceeds the 2-million-pixel budget at DPR ${ratio}`);
    assert.ok(ratio <= Math.min(context.devicePixelRatio, 1.5));
  }
  context.innerWidth = qaWidth; context.innerHeight = qaHeight; context.devicePixelRatio = qaDpr; World.resize();
});

check('every level renders all logical crates in one instance batch', () => {
  for (const level of LEVELS) {
    g.opts.level = level.id; Game._qa.startRound();
    const count = World.softCount(); const crates = World.group.getObjectByName('ArenaCrates');
    assert.equal(crates?.count || 0, count, level.id);
    assert.ok(count === 0 || crates.isInstancedMesh, level.id);
    crateMetrics.push({ level: level.id, crates: count, previousCrateMeshCount: count, currentCrateMeshCount: count ? 1 : 0 });
  }
});

const report = { profile: qaProfile, viewport: [qaWidth, qaHeight], dpr: qaDpr,
  pointers: { coarse: qaCoarse, fine: qaFine }, touchFirst: qaTouch,
  source: path.join(repo, 'index.html'), sourceSha256: createHash('sha256').update(html).digest('hex'), checks: results.length, results, crateMetrics,
  limitations: ['Node only: does not measure WebGL, FPS, visual smoothness or browser layout.', 'UI, audio device access and external character rig creation are stubbed.'] };
console.log(JSON.stringify(report, null, qaQuiet ? 0 : 2));
