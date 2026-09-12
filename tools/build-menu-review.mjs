// A GPU-independent visual review using the production menu markup, CSS and UI functions.
import fs from 'node:fs';import vm from 'node:vm';
const root=new URL('../',import.meta.url),s=fs.readFileSync(new URL('index.html',root),'utf8');
const css=s.match(/<style>([\s\S]*?)<\/style>/)[1];
const a=s.indexOf('      <div id="menu">'),b=s.indexOf('      <!-- Loadout.',a);
const markup=s.slice(a,b);
const levels=vm.runInNewContext(s.slice(s.indexOf('const LEVELS = ['),s.indexOf('// ---- Collectables'))+';LEVELS');
const wordmark=s.slice(s.indexOf('  const WM_HOT'),s.indexOf('  function showMenu'));
const menuCode=s.slice(s.indexOf('  const MENU_ROWS'),s.indexOf('  /* ------------------------------------------------------- the wordmark',s.indexOf('  const MENU_ROWS')));
const script=`const LEVELS=${JSON.stringify(levels)};const menu=document.getElementById('menu');const TouchPad={available:matchMedia('(pointer:coarse)').matches&&!matchMedia('(any-pointer:fine)').matches};${wordmark}${menuCode}
buildWordmark();let selected=0;const opts={level:'random',wins:1,difficulty:'normal',humans:1};
const next=(arr,value)=>arr[(arr.indexOf(value)+1)%arr.length];
bindMenu({onHover(i){selected=i;renderMenu(selected,opts);},onClick(i){selected=i;switch(MENU_ROWS[i]){case 'level':opts.level=next(['random',...LEVELS.map(l=>l.id)],opts.level);break;case 'rounds':opts.wins=next([1,2,3],opts.wins);break;case 'difficulty':opts.difficulty=next(['easy','normal','hard'],opts.difficulty);break;case 'players':opts.humans=3-opts.humans;break;case 'start':location.href='./';return;}renderMenu(selected,opts);}});renderMenu(0,opts);`;
fs.writeFileSync(new URL('menu-review.html',root),`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="build" content="pirate-tides-r1-20260912"><title>Bomberfan menu review</title><style>${css}</style></head><body><div id="ui">${markup}</div><script>${script}</script></body></html>`);
console.log('Built production-menu visual review');

const sizes=[[1440,900],[3840,2160],[1280,720],[1366,768],[1024,768],[768,1024],[844,390],[390,844]];
fs.writeFileSync(new URL('menu-review-sizes.html',root),`<!doctype html><html lang="en"><meta charset="utf-8"><title>Bomberfan menu layout review</title><style>body{margin:16px;background:#111724;color:white;font:14px system-ui}nav{display:flex;gap:8px;margin-bottom:16px}button{padding:10px;background:#24334b;color:white;border:1px solid #789;cursor:pointer}iframe{display:block;border:1px solid #789;width:1440px;height:900px}</style><nav>${sizes.map(([w,h])=>`<button data-w="${w}" data-h="${h}">${w} × ${h}</button>`).join('')}</nav><iframe title="Production menu" src="menu-review.html"></iframe><script>document.querySelectorAll('button').forEach(b=>b.onclick=()=>{const f=document.querySelector('iframe');f.style.width=b.dataset.w+'px';f.style.height=b.dataset.h+'px';});</script></html>`);
