import * as T from './three.module.min.js';

// Eye islands and bases measured from the original glTF inverse-bind matrices.
// Keeping these source ranges explicit prevents teeth, masks and props from
// being mistaken for eyes merely because they share an atlas colour.
const LAYOUTS = {"alien":[{"mesh":"Alien","ranges":[[3697,4100]],"eyes":[{"center":[-0.31889,0.32697,0.22461],"right":[0.89554,0.16976,0.41133],"up":[-0.00021,0.92453,-0.38111],"normal":[-0.44498,0.34121,0.82799],"radii":[0.16363,0.16363,0.16679]},{"center":[0.32041,0.32697,0.22426],"right":[0.89509,-0.16976,-0.41231],"up":[-0.00021,0.92453,-0.38111],"normal":[0.44589,0.34121,0.8275],"radii":[0.16363,0.16363,0.16679]}]}],"bunny":[{"mesh":"Bunny","ranges":[[3322,3725]],"eyes":[{"center":[-0.33696,0.30017,0.18699],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37904],"normal":[-0.26558,0.36538,0.89217],"radii":[0.1632,0.1632,0.16624]},{"center":[0.33844,0.30017,0.18662],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37904],"normal":[0.26656,0.36538,0.89188],"radii":[0.1632,0.1632,0.16624]}]}],"cactoro":[{"mesh":"Cactoro","ranges":[[3462,3865]],"eyes":[{"center":[-0.33808,0.31093,0.19406],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37904],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16374,0.16374,0.16679]},{"center":[0.33957,0.31093,0.19369],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37904],"normal":[0.26656,0.36538,0.89188],"radii":[0.16374,0.16374,0.16679]}]}],"demon":[{"mesh":"Demon","ranges":[[2570,2973]],"eyes":[{"center":[-0.33622,0.27419,0.31407],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37904],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16398,0.16398,0.16703]},{"center":[0.33785,0.27419,0.3137],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37904],"normal":[0.26656,0.36538,0.89188],"radii":[0.16398,0.16398,0.16703]}]}],"dino":[{"mesh":"Dino","ranges":[[2641,2842],[2892,3093]],"eyes":[{"center":[-0.37858,0.51968,0.09139],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37905],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16374,0.16374,0.16679]},{"center":[0.37996,0.51968,0.09098],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37905],"normal":[0.26656,0.36538,0.89188],"radii":[0.16374,0.16374,0.16679]}]}],"evolved-dragon":[{"mesh":"Dragon","ranges":[[3929,4341]],"eyes":[{"center":[-0.35606,0.20508,-0.207],"right":[0.96388,0.2328,-0.12937],"up":[-0.00048,-0.48422,-0.87494],"normal":[-0.26633,0.84341,-0.46662],"radii":[0.17983,0.17983,0.18318]},{"center":[0.36241,0.20508,-0.20739],"right":[0.97153,-0.20724,0.1148],"up":[-0.00048,-0.48629,-0.8738],"normal":[0.23691,0.84887,-0.47254],"radii":[0.17973,0.17981,0.1831]}]}],"evolved-goleling":[{"mesh":"Goleling_Evolved","ranges":[[2606,3018]],"eyes":[{"center":[-0.43516,0.24078,-0.25148],"right":[0.96595,0.24604,-0.07996],"up":[-0.00052,-0.30722,-0.95164],"normal":[-0.25871,0.91928,-0.29663],"radii":[0.19973,0.19973,0.20153]},{"center":[0.43616,0.24078,-0.25196],"right":[0.96604,-0.24605,0.0789],"up":[-0.00052,-0.30722,-0.95164],"normal":[0.25839,0.91928,-0.29692],"radii":[0.19973,0.19973,0.20153]}]}],"fish-monster":[{"mesh":"Fish","ranges":[[3084,3487]],"eyes":[{"center":[-0.30589,0.45294,0.17045],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37905],"normal":[-0.26558,0.36538,0.89217],"radii":[0.1642,0.1642,0.16726]},{"center":[0.30735,0.45294,0.17011],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37905],"normal":[0.26656,0.36538,0.89188],"radii":[0.1642,0.1642,0.16726]}]}],"flying-tribal":[{"mesh":"Tribal_Flying","ranges":[[1459,1660],[2033,2238]],"eyes":[{"center":[-0.47283,0.06402,0.06952],"right":[0.96658,0.22496,-0.12297],"up":[-0.00048,-0.47803,-0.87834],"normal":[-0.25638,0.84904,-0.46195],"radii":[0.23052,0.23053,0.23473]},{"center":[0.47418,0.06402,0.069],"right":[0.96402,-0.2328,0.12831],"up":[-0.00048,-0.48423,-0.87494],"normal":[0.26581,0.8434,-0.46692],"radii":[0.23045,0.23045,0.23474]}]}],"frog":[{"mesh":"Frog","ranges":[[2331,2762]],"eyes":[{"center":[-0.29882,0.4767,0.23642],"right":[0.93032,0.21063,0.30023],"up":[-0.00032,0.81908,-0.57367],"normal":[-0.36675,0.53361,0.76208],"radii":[0.16364,0.16364,0.16679]},{"center":[0.30036,0.4767,0.23609],"right":[0.92999,-0.21063,-0.30125],"up":[-0.00032,0.81908,-0.57367],"normal":[0.36759,0.53361,0.76167],"radii":[0.16364,0.16364,0.16679]}]}],"monkroose":[{"mesh":"Monkroose","ranges":[[2940,3141],[3293,3494]],"eyes":[{"center":[-0.33808,0.34561,0.18102],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37904],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16374,0.16374,0.16679]},{"center":[0.33956,0.34561,0.18065],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37904],"normal":[0.26656,0.36538,0.89188],"radii":[0.16374,0.16374,0.16679]}]}],"mushroom-king":[{"mesh":"MushroomKing","ranges":[[1570,1973]],"eyes":[{"center":[-0.33807,0.30393,0.19669],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37905],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16374,0.16374,0.16679]},{"center":[0.33957,0.30393,0.19632],"right":[0.96382,-0.10085,-0.24674],"up":[-0.00021,0.92538,-0.37905],"normal":[0.26656,0.36538,0.89188],"radii":[0.16374,0.16374,0.16679]}]}],"ninja":[{"mesh":"Ninja","ranges":[[1672,2098]],"eyes":[{"center":[-0.29816,0.31112,0.34513],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37904],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16374,0.16374,0.16679]},{"center":[0.29982,0.31112,0.3448],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37904],"normal":[0.26656,0.36538,0.89188],"radii":[0.16374,0.16374,0.16679]}]}],"orc":[{"mesh":"Orc","ranges":[[3398,3807]],"eyes":[{"center":[-0.26428,0.41164,0.28206],"right":[0.95198,0.11634,0.28321],"up":[-0.00021,0.92524,-0.37939],"normal":[-0.30617,0.36111,0.88083],"radii":[0.13871,0.13871,0.14133]},{"center":[0.26587,0.41164,0.28176],"right":[0.95166,-0.11634,-0.28425],"up":[-0.00021,0.92524,-0.37939],"normal":[0.30714,0.36111,0.88049],"radii":[0.13871,0.13871,0.14133]}]}],"skull-orc":[{"mesh":"Orc_Skull","ranges":[],"eyes":[{"center":[-0.253,0.45,0.532],"right":[1,0,0],"up":[0,1,0],"normal":[0,0,1],"radii":[0.115,0.132,0.07]},{"center":[0.253,0.45,0.532],"right":[1,0,0],"up":[0,1,0],"normal":[0,0,1],"radii":[0.115,0.132,0.07]}]}],"squidle":[{"mesh":"Squidle.002","ranges":[[96,525]],"eyes":[{"center":[-0.34782,0.25103,0.01585],"right":[0.89852,0.42755,-0.09933],"up":[-0.00054,-0.22522,-0.97431],"normal":[-0.43894,0.87549,-0.20213],"radii":[0.2322,0.2322,0.23379]},{"center":[0.34912,0.25103,0.01546],"right":[0.88414,-0.45577,0.1028],"up":[-0.00054,-0.221,-0.97527],"normal":[0.46722,0.86222,-0.19564],"radii":[0.23202,0.23214,0.23367]}]}],"tribal":[{"mesh":"Tribal","ranges":[[2619,3022]],"eyes":[{"center":[-0.33808,0.31752,0.19158],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37904],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16374,0.16374,0.16679]},{"center":[0.33956,0.31752,0.19121],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37904],"normal":[0.26656,0.36538,0.89188],"radii":[0.16374,0.16374,0.16679]}]}],"yeti":[{"mesh":"Yeti","ranges":[[2222,2432],[2665,2874]],"eyes":[{"center":[-0.30737,0.3394,0.29089],"right":[0.96409,0.10085,0.24568],"up":[-0.00021,0.92538,-0.37904],"normal":[-0.26558,0.36538,0.89217],"radii":[0.16374,0.16374,0.16679]},{"center":[0.30896,0.3394,0.29055],"right":[0.96382,-0.10085,-0.24675],"up":[-0.00021,0.92538,-0.37904],"normal":[0.26656,0.36538,0.89188],"radii":[0.16374,0.16374,0.16679]}]}]};

// Reference numbers refer to the user's 25-eye contact sheet. Variation is in
// silhouette, lids, iris/pupil proportions and gaze, not just iris hue.
export const EYE_STYLES = Object.freeze({
  bunny: { label: 'Alert plum irises', refs: [18,25], iris:0x9956b8, size:.62, pupil:[.33,.42], shape:[.96,1.12], lid:.76, lidColor:0xb76e9c },
  alien: { label: 'Glossy alien beads', refs:[4,20], iris:0x38c7b5, white:0x183747, size:.81, pupil:[.69,.77], shape:[.82,1.16], lid:.96, lidColor:0x591875 },
  'evolved-dragon': { label:'Amber predator slits', refs:[10,23], iris:0xffb62f, white:0xffeed0, size:.76, pupil:[.115,.58], shape:[1.05,.79], lid:.40, slant:.24, lidColor:0xab391b },
  'skull-orc': { label:'Embers inside skull sockets', refs:[4,12], iris:0xff9429, white:0x180e18, size:.33, pupil:[.10,.15], shape:[1,.93], lid:.94, glow:.3, shine:.4, lidColor:0x3e2829 },
  orc: { label:'Asymmetric sly stare', refs:[1,9], iris:0xbd8a32, white:0xf4eccf, size:.68, pupil:[.36,.40], shape:[1.13,.93], lid:[.08,.43], lidColor:0x668e27 },
  'fish-monster': { label:'Round ocean-blue irises', refs:[7,15], iris:0x167ccc, white:0xe9fff6, size:.77, pupil:[.42,.45], shape:[1.05,1.02], lid:.88, lidColor:0x238aab },
  demon: { label:'Unhinged mismatched stare', refs:[8,17], iris:[0xffad33,0xf0d82c], white:0xffe4eb, size:.43, pupil:[.17,.21], shape:[1,1.08], asym:[1.10,.90], lid:[.91,.45], lidColor:0x9b102b },
  tribal: { label:'Wide carved-mask eyes', refs:[5,21], iris:0xbf8537, white:0xffeac2, size:.79, pupil:[.64,.69], shape:[1.06,.87], lid:.68, lidColor:0x537528 },
  cactoro: { label:'Small glossy seed eyes', refs:[14,20], iris:0x6b803d, white:0xdde6b4, size:.80, pupil:[.75,.72], shape:[.86,.72], lid:.95, lidColor:0x4a812a },
  yeti: { label:'Open icy-blue eyes', refs:[13,19], iris:0x41a8df, white:0xf8f7ed, size:.66, pupil:[.37,.42], shape:[1.08,1.10], lid:.83, lidColor:0x25879c },
  'mushroom-king': { label:'Heavy-lidded chartreuse stare', refs:[1,24], iris:0xb8ca38, white:0xf4dfac, size:.68, pupil:[.30,.38], shape:[1.05,.90], lid:[.07,.24], lidColor:0x9b713f },
  ninja: { label:'Narrow crimson focus', refs:[9,16], iris:0xcb455f, white:0xffecdc, size:.60, pupil:[.24,.40], shape:[1.12,.59], lid:.39, slant:.20, lidColor:0x101321 },
  'evolved-goleling': { label:'Wild small-pupil stare', refs:[8,17], iris:0xf09d22, white:0xfff1bc, size:.42, pupil:[.17,.21], shape:[1,1.10], asym:[1.08,.91], lid:[.93,.62], lidColor:0x788d25 },
  monkroose: { label:'Bright forest-green irises', refs:[3,18], iris:0x348252, white:0xfff3d8, size:.70, pupil:[.39,.46], shape:[.96,1.07], lid:.74, lidColor:0x86a63b },
  dino: { label:'Citrus saurian slits', refs:[10,23], iris:0xb5dc35, white:0xffe7bd, size:.73, pupil:[.12,.56], shape:[1.04,.83], lid:.29, slant:.16, lidColor:0xa41958 },
  'flying-tribal': { label:'Luminous turquoise rings', refs:[19,22], iris:0x55cde0, white:0x172c39, size:.78, pupil:[.29,.35], shape:[1.06,1.02], lid:.77, glow:.12, lidColor:0x365837 },
  frog: { label:'Bronze horizontal pupils', refs:[10,24], iris:0xe0ad35, white:0x273222, size:.89, pupil:[.67,.19], shape:[1.10,.96], lid:.58, lidColor:0xb78b24 },
  squidle: { label:'Tall violet startled eyes', refs:[17,25], iris:0x8060cd, white:0xe3f5ff, size:.65, pupil:[.37,.49], shape:[.88,1.20], lid:[.87,.54], lidColor:0xb63878 },
});

// One continuous glossy sphere per eye. Procedural surface artwork avoids
// overlapping iris geometry, z-fighting and extra material draw calls.
const eyeGeometry=new T.SphereGeometry(1,20,12);
const geometryCache=new Map();
let eyeAtlas=null;
let atlasReady=null;
function atlasTexture(){
  if(!eyeAtlas){
    atlasReady=new Promise((resolve,reject)=>{
      eyeAtlas=new T.TextureLoader().load(new URL('../characters/roster-eye-atlas.png',import.meta.url).href,resolve,undefined,reject);
    });
    eyeAtlas.colorSpace=T.SRGBColorSpace;eyeAtlas.anisotropy=4;
    // Prevent neighbouring atlas tiles bleeding into each other in coarse mips.
    eyeAtlas.generateMipmaps=false;eyeAtlas.minFilter=T.LinearFilter;
    eyeAtlas.userData.sharedEyeTexture=true;
  }
  return eyeAtlas;
}
export function preloadRosterEyes(){atlasTexture();return atlasReady;}
function atlasGeometry(id,side){
  const tile=Object.keys(EYE_STYLES).indexOf(id)*2+side;
  if(!geometryCache.has(tile)){
    const geometry=eyeGeometry.clone(),uv=geometry.attributes.uv;
    const x=tile%6*260,y=Math.floor(tile/6)*132;
    for(let i=0;i<uv.count;i++){
      const u=T.MathUtils.clamp(uv.getX(i),0,1),v=T.MathUtils.clamp(uv.getY(i),0,1);
      uv.setXY(i,(x+2.5+u*255)/1560,1-(y+2.5+(1-v)*127)/792);
    }
    geometryCache.set(tile,geometry);
  }
  return geometryCache.get(tile);
}

export function addRosterEyes(model,def){
  const style=EYE_STYLES[def.id];
  if(!style)return false;
  const head=model.getObjectByName('Head');
  if(!head||head.getObjectByName('RosterEyes'))return false;
  const face=new T.Group();face.name='RosterEyes';face.userData.eyeStyle=style.label;
  let eyeNumber=0;
  for(const layout of LAYOUTS[def.id]){
    const source=model.getObjectByName(T.PropertyBinding.sanitizeNodeName(layout.mesh));
    if(!source?.isSkinnedMesh)continue;
    if(layout.ranges.length){
      const geometry=source.geometry.clone(),keep=[];
      const hidden=i=>layout.ranges.some(([a,b])=>i>=a&&i<=b);
      for(let i=0;i<geometry.index.count;i+=3){
        const a=geometry.index.getX(i),b=geometry.index.getX(i+1),c=geometry.index.getX(i+2);
        if(!hidden(a)&&!hidden(b)&&!hidden(c))keep.push(a,b,c);
      }
      geometry.setIndex(keep);source.geometry=geometry;source.userData.sharedModelGeometry=false;
    }
    for(const eye of layout.eyes){
      const side=eyeNumber++%2,factor=style.asym?.[side]||1;
      const map=atlasTexture();
      const material=new T.MeshStandardMaterial({map,roughness:.24,metalness:0,
        emissiveMap:style.glow?map:null,emissive:style.glow?0xffffff:0,emissiveIntensity:style.glow||0});
      const mesh=new T.Mesh(atlasGeometry(def.id,side),material);mesh.name=side===0?'EyeLeft':'EyeRight';
      mesh.position.set(...eye.center);
      mesh.quaternion.setFromRotationMatrix(new T.Matrix4().makeBasis(new T.Vector3(...eye.right),new T.Vector3(...eye.up),new T.Vector3(...eye.normal)));
      mesh.scale.set(eye.radii[0]*style.shape[0]*factor,eye.radii[1]*style.shape[1]*factor,eye.radii[2]);
      mesh.userData.sharedModelGeometry=true;
      face.add(mesh);
    }
  }
  face.userData.eyeCount=eyeNumber;head.add(face);return true;
}
