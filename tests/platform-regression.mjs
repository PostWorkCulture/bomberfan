import assert from 'node:assert/strict';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const test = path.join(path.dirname(fileURLToPath(import.meta.url)), 'simulation-regression.mjs');
const profiles = [
  { name: 'Windows/macOS desktop', width: 1440, height: 900, dpr: 1, coarse: false, fine: true, touch: false },
  { name: '4K desktop', width: 3840, height: 2160, dpr: 2, coarse: false, fine: true, touch: false },
  { name: 'Chromebook/laptop', width: 1280, height: 720, dpr: 1.25, coarse: false, fine: true, touch: false },
  // A touchscreen laptop must retain desktop input/layout because a fine
  // pointer is also available. This is distinct from a touch-first tablet.
  { name: 'Hybrid touchscreen laptop', width: 1366, height: 768, dpr: 1.25, coarse: true, fine: true, touch: false },
  { name: 'iPad/tablet landscape', width: 1024, height: 768, dpr: 2, coarse: true, fine: false, touch: true },
  { name: 'iPad/tablet portrait', width: 768, height: 1024, dpr: 2, coarse: true, fine: false, touch: true },
  { name: 'Android/iPhone landscape', width: 844, height: 390, dpr: 3, coarse: true, fine: false, touch: true },
  { name: 'Android/iPhone portrait', width: 390, height: 844, dpr: 3, coarse: true, fine: false, touch: true },
];

const passes = [];
for (let round = 1; round <= 2; round++) {
  for (const profile of profiles) {
    const run = spawnSync(process.execPath, [test], {
      encoding: 'utf8',
      env: {
        ...process.env,
        BF_QA_PROFILE: profile.name,
        BF_QA_WIDTH: String(profile.width),
        BF_QA_HEIGHT: String(profile.height),
        BF_QA_DPR: String(profile.dpr),
        BF_QA_COARSE: profile.coarse ? '1' : '0',
        BF_QA_FINE: profile.fine ? '1' : '0',
        BF_QA_TOUCH: profile.touch ? '1' : '0',
        BF_QA_QUIET: '1',
      },
    });
    assert.equal(run.status, 0, `${profile.name}, pass ${round}\n${run.stdout}\n${run.stderr}`);
    const lines = run.stdout.trim().split(/\r?\n/);
    const result = JSON.parse(lines.at(-1));
    assert.equal(result.checks, 16);
    assert.equal(result.results.every(check => check.passed), true);
    assert.deepEqual(result.viewport, [profile.width, profile.height]);
    assert.deepEqual(result.pointers, { coarse: profile.coarse, fine: profile.fine });
    assert.equal(result.touchFirst, profile.touch);
    passes.push({ round, profile: profile.name, viewport: result.viewport, checks: result.checks });
    console.log(`PASS ${round}/2 ${profile.name} ${profile.width}x${profile.height}: ${result.checks} checks`);
  }
}

console.log(JSON.stringify({ profiles: profiles.length, rounds: 2, runs: passes.length, checks: passes.length * 16, passes }, null, 2));
