// A GPU-independent visual review using the production menu markup, CSS and UI functions.
import fs from 'node:fs';import vm from 'node:vm';
const root=new URL('../',import.meta.url),s=fs.readFileSync(new URL('index.html',root),'utf8');
const css=s.match(/<style>([\s\S]*?)<\/style>/)[1];
const a=s.indexOf('      <div id="menu">'),b=s.indexOf('      <!-- Loadout.',a);
const markup=s.slice(a,b);
const levels=vm.runInNewContext(s.slice(s.indexOf('const LEVELS = ['),s.indexOf('// ---- Collectables'))+';LEVELS');
const wordmark=s.slice(s.indexOf('  const WM_HOT'),s.indexOf('  function showMenu'));
const menuCode=s.slice(s.indexOf('  const MENU_ROWS'),s.indexOf('  /* ------------------------------------------------------- the wordmark'));
const script=`const LEVELS=${JSON.stringify(levels)};const menu=document.getElementById('menu');const TouchPad={available:matchMedia('(pointer:coarse)').matches&&!matchMedia('(any-pointer:fine)').matches};${wordmark}${menuCode}
buildWordmark();let selected=0;const opts={level:'random',wins:1,difficulty:'normal',humans:1};
const next=(arr,value)=>arr[(arr.indexOf(value)+1)%arr.length];
bindMenu({onHover(i){selected=i;renderMenu(selected,opts);},onClick(i){selected=i;switch(MENU_ROWS[i]){case 'level':opts.level=next(['random',...LEVELS.map(l=>l.id)],opts.level);break;case 'rounds':opts.wins=next([1,2,3],opts.wins);break;case 'difficulty':opts.difficulty=next(['easy','normal','hard'],opts.difficulty);break;case 'players':opts.humans=3-opts.humans;break;case 'start':location.href='./';return;}renderMenu(selected,opts);}});renderMenu(0,opts);`;
fs.writeFileSync(new URL('menu-review.html',root),`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="build" content="pirate-tides-r1-20260912"><title>Bomberfan menu review</title><style>${css}</style></head><body><div id="ui">${markup}</div><script>${script}</script></body></html>`);
console.log('Built production-menu visual review');
