from pathlib import Path

p = Path('index.html')
s = p.read_text(encoding='utf-8')

s = s.replace('<h2>PRIZE LOCKER</h2>', '<h2>LOADOUT</h2>')

marker = '/* BOMBER FAN VISUAL POLISH V3 */'
if marker not in s:
    css = r'''
  /* BOMBER FAN VISUAL POLISH V3 */

  /* Blend the square logo artwork into the menu so it reads as part of the scene. */
  #menu h1 {
    background-size: 112% !important;
    -webkit-mask-image: radial-gradient(ellipse at center, #000 0 58%, rgba(0,0,0,.98) 66%, rgba(0,0,0,.72) 78%, transparent 100%);
    mask-image: radial-gradient(ellipse at center, #000 0 58%, rgba(0,0,0,.98) 66%, rgba(0,0,0,.72) 78%, transparent 100%);
    filter:
      drop-shadow(0 18px 22px rgba(0,0,0,.76))
      drop-shadow(0 0 42px rgba(255,119,15,.48))
      saturate(1.05) contrast(1.03) !important;
  }
  #menu h1::before {
    content: ''; position: absolute; inset: -12%; z-index: -1; pointer-events: none;
    background: radial-gradient(ellipse at center, rgba(255,124,22,.20), rgba(255,94,13,.08) 40%, transparent 72%);
    filter: blur(14px);
  }

  /* LOADOUT — tactical armoury / war-room pass. */
  #select {
    background: transparent !important;
  }
  #select .sbg {
    background:
      radial-gradient(900px 540px at 50% -10%, rgba(255,164,63,.23), transparent 56%),
      radial-gradient(700px 520px at 16% 46%, rgba(255,112,18,.11), transparent 64%),
      linear-gradient(180deg, rgba(18,20,23,.98), rgba(8,9,11,.99)) !important;
  }
  #select .sbg::before {
    content: '';
    position: absolute; inset: 0; pointer-events: none;
    background:
      /* overhead industrial light bars */
      linear-gradient(90deg, transparent 0 12%, rgba(255,177,82,.18) 12.3% 12.8%, rgba(255,229,182,.32) 13% 17%, rgba(255,177,82,.18) 17.2% 17.7%, transparent 18% 82%, rgba(255,177,82,.18) 82.3% 82.8%, rgba(255,229,182,.32) 83% 87%, rgba(255,177,82,.18) 87.2% 87.7%, transparent 88%),
      /* steel wall panel seams */
      repeating-linear-gradient(90deg, transparent 0 11.7%, rgba(255,255,255,.025) 11.8% 12%, transparent 12.1% 24%),
      repeating-linear-gradient(0deg, transparent 0 72px, rgba(255,255,255,.022) 73px 74px),
      /* tactical schematic glow */
      radial-gradient(circle at 78% 35%, transparent 0 72px, rgba(255,136,31,.055) 73px 75px, transparent 76px 98px, rgba(255,136,31,.035) 99px 101px, transparent 102px),
      linear-gradient(135deg, transparent 0 49.4%, rgba(255,142,35,.035) 49.6% 50.4%, transparent 50.6% 100%);
    box-shadow: inset 0 0 120px rgba(0,0,0,.72);
    opacity: .92;
  }
  #select .sbg::after {
    content: ''; position: absolute; inset: -8%; pointer-events: none;
    background:
      radial-gradient(1.4px 1.4px at 13% 20%, rgba(255,194,99,.86), transparent),
      radial-gradient(1.2px 1.2px at 36% 72%, rgba(255,107,26,.72), transparent),
      radial-gradient(1.5px 1.5px at 72% 18%, rgba(255,223,156,.72), transparent),
      radial-gradient(1.2px 1.2px at 88% 66%, rgba(255,127,33,.66), transparent),
      linear-gradient(180deg, rgba(255,153,47,.035), transparent 22%, transparent 76%, rgba(255,102,17,.03));
    background-size: 143px 143px, 187px 187px, 223px 223px, 169px 169px, auto;
    filter: drop-shadow(0 0 5px rgba(255,114,19,.42));
    opacity: .42;
    animation: armourEmbersV3 8s linear infinite alternate;
  }
  @keyframes armourEmbersV3 { from { transform: translateY(0); } to { transform: translateY(-10px); } }

  #select .shead {
    position: relative;
    justify-content: center;
    border-bottom: none !important;
    padding-bottom: 8px !important;
  }
  #select .shead::before,
  #select .shead::after {
    content: ''; height: 2px; flex: 1; max-width: 180px;
    background: linear-gradient(90deg, transparent, rgba(255,156,50,.55));
    box-shadow: 0 0 10px rgba(255,115,18,.18);
  }
  #select .shead::after { transform: scaleX(-1); }
  #select h2 {
    font-family: 'Arial Black', 'Arial Bold', 'Helvetica Neue', Impact, system-ui, sans-serif !important;
    font-size: clamp(24px, 3.8vw, 42px) !important;
    letter-spacing: 6px !important;
    color: #f4e7cf !important;
    text-shadow: 0 3px 0 #000, 0 0 24px rgba(255,126,24,.28) !important;
  }
  #select h2::before { display: none !important; }

  /* Create the visual language of wall lockers and kit cages around the playable preview. */
  #select .sbody {
    position: relative;
    padding: 12px clamp(10px, 2vw, 24px) 18px;
    border-radius: 18px;
    background:
      linear-gradient(180deg, rgba(17,19,22,.34), rgba(5,6,8,.58)),
      repeating-linear-gradient(90deg, rgba(255,255,255,.018) 0 1px, transparent 1px 88px);
    border: 1px solid rgba(255,157,51,.10);
    box-shadow: inset 0 1px 0 rgba(255,255,255,.025), 0 20px 50px rgba(0,0,0,.28);
  }
  #select .sbody::before {
    content: '';
    position: absolute; left: 0; right: 0; bottom: 0; height: 14px; pointer-events: none;
    border-radius: 0 0 18px 18px;
    background: repeating-linear-gradient(135deg, #d47a18 0 13px, #151515 13px 26px);
    opacity: .56;
    box-shadow: 0 -3px 10px rgba(0,0,0,.40);
  }
  #select .sbody::after {
    content: 'TACTICAL ARMOURY  //  KIT ISSUE  //  MATCH PREP';
    position: absolute; right: 18px; top: 8px; pointer-events: none;
    color: rgba(255,177,79,.30);
    font: 900 8px/1 system-ui, sans-serif;
    letter-spacing: 2px;
  }

  #spreview {
    border: 1px solid rgba(255,163,58,.60) !important;
    background:
      linear-gradient(180deg, rgba(255,140,32,.035), transparent 28%),
      repeating-linear-gradient(90deg, transparent 0 24px, rgba(255,255,255,.018) 25px 26px) !important;
    box-shadow:
      0 0 0 1px rgba(0,0,0,.78),
      inset 0 0 44px rgba(255,121,21,.05),
      0 0 34px rgba(255,109,15,.15),
      0 18px 38px rgba(0,0,0,.42) !important;
  }
  #spreview::before {
    content: 'ARMOUR BAY 01  //  READY';
    color: rgba(255,208,139,.82) !important;
    border-color: rgba(255,157,48,.44) !important;
    background: rgba(8,9,11,.82) !important;
  }
  #spreview::after {
    content: '';
    position: absolute; inset: 11% 10% 8%; pointer-events: none; z-index: 1;
    border: 1px solid rgba(255,166,66,.12);
    border-top-color: rgba(255,183,92,.25);
    border-bottom-color: rgba(255,113,18,.25);
    clip-path: polygon(0 0, 16% 0, 16% 1px, 84% 1px, 84% 0, 100% 0, 100% 18%, calc(100% - 1px) 18%, calc(100% - 1px) 82%, 100% 82%, 100% 100%, 84% 100%, 84% calc(100% - 1px), 16% calc(100% - 1px), 16% 100%, 0 100%, 0 82%, 1px 82%, 1px 18%, 0 18%);
    opacity: .65;
  }

  #select .slist {
    position: relative;
    padding: 14px 12px 12px !important;
    background:
      linear-gradient(180deg, rgba(27,30,34,.92), rgba(8,9,11,.94)) !important;
    border: 1px solid rgba(255,156,48,.22) !important;
    box-shadow:
      inset 0 1px 0 rgba(255,255,255,.035),
      inset 0 0 28px rgba(255,115,17,.025),
      0 18px 42px rgba(0,0,0,.40) !important;
  }
  #select .slist::before {
    content: 'EQUIPMENT LOCKERS';
    position: absolute; left: 14px; top: -9px;
    padding: 3px 8px;
    background: #111317;
    border: 1px solid rgba(255,154,47,.28);
    color: rgba(255,190,101,.66);
    font: 900 8px/1 system-ui, sans-serif;
    letter-spacing: 1.8px;
    border-radius: 4px;
  }
  .sitem {
    border-left: 3px solid rgba(255,135,28,.18) !important;
  }
  .sitem.sel, .sitem:hover, .sitem.on {
    border-left-color: #ff9c31 !important;
  }

  #select .sfoot .opt.go {
    position: relative;
    overflow: hidden;
    letter-spacing: 1px;
  }
  #select .sfoot .opt.go::before {
    content: '';
    position: absolute; inset: 0; pointer-events: none;
    background: linear-gradient(110deg, transparent 0 42%, rgba(255,220,155,.10) 51%, transparent 60% 100%);
    transform: translateX(-70%);
    animation: fightSweep 2.8s ease-in-out infinite;
  }
  @keyframes fightSweep {
    0%, 58% { transform: translateX(-70%); }
    82%, 100% { transform: translateX(75%); }
  }

  @media (prefers-reduced-motion: reduce) {
    #select .sbg::after, #select .sfoot .opt.go::before { animation: none !important; }
  }
  @media (max-height: 460px) {
    #select .sbody { padding: 5px 7px 11px; border-radius: 10px; }
    #select .sbody::before { height: 8px; border-radius: 0 0 10px 10px; background-size: 18px 18px; }
    #select .sbody::after { display: none; }
    #select h2 { font-size: 17px !important; letter-spacing: 4px !important; }
    #select .shead::before, #select .shead::after { max-width: 80px; }
    #select .slist { padding: 6px !important; }
    #select .slist::before { display: none; }
  }
'''
    s = s.replace('</style>', css + '\n</style>', 1)

p.write_text(s, encoding='utf-8')
