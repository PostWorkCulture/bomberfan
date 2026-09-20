import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(scriptDir, '..');

const html = fs.readFileSync(path.join(repo, 'index.html'), 'utf8');
const source = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes('const Game ='));
assert.ok(source, 'embedded game script found');

// Verify configuration additions
assert.ok(source.includes("LINEBOMB: 'linebomb'"), 'PU.LINEBOMB defined');
assert.ok(source.includes("id: PU.LINEBOMB"), 'PU.LINEBOMB in PU_TABLE');
assert.ok(source.includes("[PU.LINEBOMB]: 'L'"), 'PU.LINEBOMB in PU_CODE');
assert.ok(source.includes("id: PU.REMOTE"), 'PU.REMOTE in PU_DROPS');
assert.ok(source.includes("id: PU.SHIELD"), 'PU.SHIELD in PU_DROPS');
assert.ok(source.includes("id: PU.PIERCE"), 'PU.PIERCE in PU_DROPS');
assert.ok(source.includes("id: PU.LINEBOMB"), 'PU.LINEBOMB in PU_DROPS');

// Verify GLYPH
assert.ok(source.includes("[PU.LINEBOMB](g)"), 'Line bomb glyph renderer present');

// Verify Audio3
assert.ok(source.includes("lineBomb()"), 'Audio3.lineBomb present');
assert.ok(source.includes("remoteTrigger()"), 'Audio3.remoteTrigger present');

// Verify Entities
assert.ok(source.includes("group.userData.shieldBubble = bubble"), 'Shield bubble created on player mesh');
assert.ok(source.includes("this.lineBomb = false"), 'Player lineBomb flag initialized');
assert.ok(source.includes("case PU.LINEBOMB:  player.lineBomb = true; break;"), 'PowerUp applies lineBomb');
assert.ok(source.includes("function doLineBomb(player)"), 'doLineBomb function implemented');

console.log('PASS Phase 1 Power-ups & Combat Mechanics syntax and integration verified.');
