// Runs the production HUD updater without a browser; checks DOM work, not layout.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const repo = path.resolve(process.argv[2] || path.join(path.dirname(fileURLToPath(import.meta.url)), '..'));
const source = fs.readFileSync(path.join(repo, 'index.html'), 'utf8');
const start = source.indexOf('  function updateHUD(game) {');
const end = source.indexOf('  function showHUD(', start);
assert.ok(start >= 0 && end > start);
const counters = {writes: 0, measures: 0};
function node() {
  const classes = new Set(); let text = '';
  const wins = {get textContent(){return text;}, set textContent(v){text=v; counters.writes++;}};
  return {
    _wins: wins, querySelector: () => wins,
    classList: {contains: c => classes.has(c), toggle(c,on){counters.writes++; on ? classes.add(c) : classes.delete(c);}},
  };
}
const cards = Array.from({length:4}, node), clock = node();
const layout = () => counters.measures++;
const api = new Function('cards', 'document', 'STATE', 'placeCards', 'dropCards', 'placeClock', 'hudReserveTop', 'World', `
 let hudLayoutDirty = true, lastReserve = -1;
 ${source.slice(start,end)}
 return { updateHUD, invalidate() { hudLayoutDirty = true; } };
`)(cards, {getElementById:()=>clock}, {PLAY:3}, layout, layout, layout, () => {layout();return 60;}, {fit:layout});
const game = {players: Array.from({length:4}, (_,seat)=>({seat,alive:true,curse:null,wins:0})), opts:{wins:3}, suddenDeath:false,state:3};
api.updateHUD(game);
counters.writes=counters.measures=0;
for(let i=0;i<600;i++)api.updateHUD(game);
assert.deepEqual(counters, {writes:0,measures:0}, 'unchanged HUD must cause no repeated DOM writes or layout measurements');
game.players[0].wins=1; api.updateHUD(game);
assert.equal(cards[0]._wins.textContent,'1/3');
assert.ok(counters.measures>0, 'score width changes trigger a layout update');
counters.writes=counters.measures=0;
game.players[1].alive=false; game.players[2].curse='slow'; api.updateHUD(game);
assert.ok(cards[1].classList.contains('dead')); assert.ok(cards[2].classList.contains('cursed'));
assert.equal(counters.measures,0, 'status styling should not force unchanged card layout');
api.invalidate(); api.updateHUD(game); assert.ok(counters.measures>0, 'viewport/font invalidation refreshes layout');
counters.writes=counters.measures=0;
game.suddenDeath=true;api.updateHUD(game);assert.ok(clock.classList.contains('sd'));assert.ok(counters.measures>0);
console.log('PASS HUD: 600 unchanged updates produce zero DOM writes/layout measurements; scores, status, layout invalidation and sudden death remain responsive.');
