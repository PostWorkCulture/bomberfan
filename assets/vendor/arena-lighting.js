import * as T from './three.module.min.js';

// A Theme-aware art treatment. No simulation state, random stream or source
// character materials are changed. Asset failure leaves the original art usable.
export const ARENA_PROFILES = Object.freeze({
  forest: {key:0xffdfad, fill:0x9abccc, sky:0xc2dceb, bounce:0x535132, background:0x13271e, power:2.7, exposure:1.05, environment:.42, roughness:.92, crate:.72, glow:.12},
  beach: {key:0xffeed0, fill:0x77c6e9, sky:0xc3e8ff, bounce:0x5b958e, background:0x10394a, power:2.65, exposure:1.04, environment:.48, roughness:.32, crate:.74, glow:.08},
  glacier: {key:0xd7eeff, fill:0x839fe7, sky:0xd3edff, bounce:0x52789b, background:0x152c45, power:2.55, exposure:1.04, environment:.55, roughness:.38, crate:.34, glow:.10},
  haunted: {key:0xd8d9ff, fill:0xa998ce, sky:0xaaaed5, bounce:0x594b69, background:0x211a32, power:2.35, exposure:1.12, environment:.42, roughness:.78, crate:.65, glow:.12},
  'haunted-train': {key:0xd6e9ff, fill:0x78cec5, sky:0xb5c3ed, bounce:0x63436b, background:0x211731, power:2.45, exposure:1.08, environment:.5, roughness:.48, crate:.53, glow:.09},
  factory: {key:0xffdfb3, fill:0x96bcd5, sky:0xc6d9e1, bounce:0x625449, background:0x252a2c, power:2.55, exposure:1.05, environment:.55, roughness:.57, crate:.54, glow:.10},
  circuit: {key:0xd3eaff, fill:0x88cfdb, sky:0xb2d4eb, bounce:0x3f506e, background:0x141e32, power:2.4, exposure:1.06, environment:.52, roughness:.43, crate:.48, glow:.08},
  pirate: {key:0xffe0b6, fill:0x88bfd6, sky:0xc2deed, bounce:0x675141, background:0x153b47, power:2.65, exposure:1.05, environment:.52, roughness:.76, crate:.68, glow:.10},
});
const files = ['ground', 'ground-normal', 'wood', 'stone', 'ground-ao', 'ground-bounce'];
const bakedFiles = Object.keys(ARENA_PROFILES).filter(id=>id!=='forest').flatMap(id=>[id+'-ao',id+'-bounce']);
export const arenaAssets = {};
export async function preloadArenaAssets() {
  const loader = new T.TextureLoader();
  await Promise.all([...files,...bakedFiles].map(async name => {
    try {
      const texture = await loader.loadAsync(new URL(`../${files.includes(name) ? 'forest' : 'lighting'}/${name}.png`, import.meta.url).href);
      texture.colorSpace = ['ground', 'wood', 'stone'].includes(name) ? T.SRGBColorSpace : T.NoColorSpace;
      texture.anisotropy = 4;
      texture.userData.forestShared = true;
      if (name === 'ground' || name === 'ground-normal') {
        texture.wrapS = texture.wrapT = T.RepeatWrapping;
        texture.repeat.set(6, 5.2);
      }
      if (name.endsWith('-ao') || name.endsWith('-bounce')) texture.channel = 1;
      arenaAssets[name] = texture;
    } catch (e) { console.warn(`Arena ${name} unavailable; retaining fallback surface.`, e.message); }
  }));
}

export function bevelBox(w, h, d, radius = .065) {
  const geometry = new T.BoxGeometry(w, h, d, 4, 4, 4);
  const p = geometry.attributes.position, n = geometry.attributes.normal;
  const v = new T.Vector3(), inner = new T.Vector3(), normal = new T.Vector3();
  const half = new T.Vector3(w/2-radius, h/2-radius, d/2-radius);
  for (let i=0; i<p.count; i++) {
    v.fromBufferAttribute(p, i);
    inner.copy(v).clamp(half.clone().negate(), half);
    normal.copy(v).sub(inner).normalize();
    v.copy(inner).addScaledVector(normal, radius);
    p.setXYZ(i,v.x,v.y,v.z); n.setXYZ(i,normal.x,normal.y,normal.z);
  }
  geometry.computeBoundingBox(); geometry.computeBoundingSphere();
  return geometry;
}

const vertexShader = 'varying vec2 vUv; void main(){vUv=uv;gl_Position=vec4(position.xy,0.,1.);}';
const extractShader = `varying vec2 vUv; uniform sampler2D source;
void main(){vec3 c=texture2D(source,vUv).rgb; float l=max(max(c.r,c.g),c.b);
gl_FragColor=vec4(c*smoothstep(1.25,2.8,l),1.);}`;
const blurShader = `varying vec2 vUv; uniform sampler2D source; uniform vec2 stepSize;
void main(){vec3 c=texture2D(source,vUv).rgb*.227027;
c+=(texture2D(source,vUv+stepSize*1.384615).rgb+texture2D(source,vUv-stepSize*1.384615).rgb)*.316216;
c+=(texture2D(source,vUv+stepSize*3.230769).rgb+texture2D(source,vUv-stepSize*3.230769).rgb)*.070270;
gl_FragColor=vec4(c,1.);}`;
const outputShader = `varying vec2 vUv; uniform sampler2D source; uniform sampler2D glow; uniform float glowStrength;
void main(){vec3 c=texture2D(source,vUv).rgb+texture2D(glow,vUv).rgb*glowStrength;
// Mild warm highlights/cool shadows in linear light; never crush dark bombs.
float l=dot(c,vec3(.2126,.7152,.0722));
c*=mix(vec3(.96,1.,1.035),vec3(1.025,1.008,.98),smoothstep(.1,1.8,l));
gl_FragColor=vec4(c,1.);
#include <tonemapping_fragment>
#include <colorspace_fragment>
}`;

export class ArenaPost {
  constructor(renderer) {
    this.renderer=renderer; this.width=0; this.height=0;
    this.scene=new T.Scene(); this.camera=new T.Camera();
    this.quad=new T.Mesh(new T.PlaneGeometry(2,2)); this.quad.frustumCulled=false; this.scene.add(this.quad);
    const material=(fragmentShader,uniforms,toneMapped=false)=>new T.ShaderMaterial({vertexShader,fragmentShader,uniforms,depthTest:false,depthWrite:false,toneMapped});
    this.extract=material(extractShader,{source:{value:null}});
    this.blur=material(blurShader,{source:{value:null},stepSize:{value:new T.Vector2()}});
    this.output=material(outputShader,{source:{value:null},glow:{value:null},glowStrength:{value:.12}},true);
    this.size=new T.Vector2();
  }
  resize() {
    const r=this.renderer; r.getDrawingBufferSize(this.size);
    const w=Math.max(1,Math.round(this.size.x)), h=Math.max(1,Math.round(this.size.y));
    if(this.width===w&&this.height===h)return;
    this.width=w;this.height=h;
    if(!this.hdr) {
      this.hdr=new T.WebGLRenderTarget(w,h,{type:T.HalfFloatType,depthBuffer:true,samples:2});
      this.a=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,depthBuffer:false});
      this.b=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,depthBuffer:false});
    }
    this.hdr.setSize(w,h);this.a.setSize(Math.max(1,w>>2),Math.max(1,h>>2));this.b.setSize(Math.max(1,w>>2),Math.max(1,h>>2));
  }
  render(scene,camera) {
    this.resize();
    const r=this.renderer, target=r.getRenderTarget(), tm=r.toneMapping;
    try {
      r.toneMapping=T.NoToneMapping; r.setRenderTarget(this.hdr); r.render(scene,camera);
      this.extract.uniforms.source.value=this.hdr.texture;this.quad.material=this.extract;
      r.setRenderTarget(this.a);r.render(this.scene,this.camera);
      this.quad.material=this.blur;this.blur.uniforms.source.value=this.a.texture;
      this.blur.uniforms.stepSize.value.set(1/this.a.width,0);r.setRenderTarget(this.b);r.render(this.scene,this.camera);
      this.blur.uniforms.source.value=this.b.texture;this.blur.uniforms.stepSize.value.set(0,1/this.a.height);
      r.setRenderTarget(this.a);r.render(this.scene,this.camera);
      r.toneMapping=tm;this.quad.material=this.output;
      this.output.uniforms.source.value=this.hdr.texture;this.output.uniforms.glow.value=this.a.texture;
      r.setRenderTarget(target);r.render(this.scene,this.camera);
    } finally {r.toneMapping=tm;r.setRenderTarget(target);}
  }
  dispose(){for(const o of [this.hdr,this.a,this.b,this.extract,this.blur,this.output,this.quad.geometry])o?.dispose();}
}

export class ArenaLighting {
  constructor({renderer,scene,key,fill,hemi,mat,mode='auto',mobile=false}) {
    Object.assign(this,{renderer,scene,key,fill,hemi,mat,mode});
    this.active=false;this.post=null;this.envTarget=null;this.environments=new Map();this.slow=0;
    this.mobile=mobile;
    this.tier=mode==='high'?'high':mode==='balanced'?'balanced':this.mobile?'balanced':'high';
    this.originalMaterials=new Map();
    for(const name of ['ground','soft','hard','hardTop','wall','wallTop','border']) {
      const m=mat[name];
      this.originalMaterials.set(name,{roughness:m.roughness,metalness:m.metalness,color:m.color.clone(),map:m.map,normalMap:m.normalMap,aoMap:m.aoMap,lightMap:m.lightMap});
    }
  }
  get enabled(){return this.active&&this.mode!=='original';}
  prepareEnvironment(id) {
    if(this.environments.has(id)){this.envTarget=this.environments.get(id);return;}
    if( !this.renderer.isWebGLRenderer || !this.renderer.extensions.has('EXT_color_buffer_float'))return;
    // Small prefiltered HDR environment, authored in linear colour. Generated
    // only once, no cube capture or reflection work in the gameplay loop.
    const profile=ARENA_PROFILES[id];
    const keyColour=new T.Color(profile.key),skyColour=new T.Color(profile.sky),bounceColour=new T.Color(profile.bounce);
    const w=128,h=64,data=new Float32Array(w*h*4);
    for(let y=0;y<h;y++)for(let x=0;x<w;x++) {
      const v=(y+.5)/h,u=(x+.5)/w,sky=Math.max(0,-Math.cos(v*Math.PI));
      const sun=Math.exp(-((u-.22)**2/.005+(v-.71)**2/.009));
      const i=(y*w+x)*4;
      data[i]=.12+bounceColour.r*.1+sky*skyColour.r*.6+sun*keyColour.r*3.4;
      data[i+1]=.12+bounceColour.g*.1+sky*skyColour.g*.6+sun*keyColour.g*3.4;
      data[i+2]=.12+bounceColour.b*.1+sky*skyColour.b*.6+sun*keyColour.b*3.4;data[i+3]=1;
      if(id==='forest'){data[i]=.12+sky*.34+sun*3.4;data[i+1]=.18+sky*.43+sun*2.7;data[i+2]=.10+sky*.62+sun*1.6;}
    }
    const texture=new T.DataTexture(data,w,h,T.RGBAFormat,T.FloatType);
    texture.mapping=T.EquirectangularReflectionMapping;texture.needsUpdate=true;
    const pmrem=new T.PMREMGenerator(this.renderer);
    try {this.envTarget=pmrem.fromEquirectangular(texture);this.environments.set(id,this.envTarget);} finally {texture.dispose();pmrem.dispose();}
  }
  apply(level) {
    this.profile=ARENA_PROFILES[level.id];
    this.active=!!this.profile;
    const p=this.profile;
    const on=this.enabled;
    this.key.color.setHex(on?p.key:0xfff2d8);this.key.intensity=on?p.power:2;
    this.key.position.set(on?-6:7,on?13:16,on?5:8);
    this.fill.color.setHex(on?p.fill:0x88aaff);this.fill.intensity=on?.48:.5;
    this.fill.position.set(on?8:-9,on?7:8,on?-8:-7);
    this.hemi.color.setHex(on?p.sky:0xbfd8ff);this.hemi.groundColor.setHex(on?p.bounce:0x2b3b1e);
    this.hemi.intensity=on?.65:1.05;
    this.renderer.toneMappingExposure=on?p.exposure:1.15;
    this.scene.background.setHex(on?p.background:level.sky);
    this.scene.fog.color.copy(this.scene.background);this.scene.fog.near=on?31:26;this.scene.fog.far=on?54:44;
    if(on) {try{this.prepareEnvironment(level.id);}catch(e){console.warn('Arena reflections unavailable',e.message);}}
    this.scene.environment=on?(this.envTarget?.texture||null):null;
    this.scene.environmentIntensity=on?p.environment:1;
    const d=on?10:12;
    Object.assign(this.key.shadow.camera,{left:-d,right:d,top:d,bottom:-d,near:1,far:45});
    this.key.shadow.camera.updateProjectionMatrix();
    this.key.shadow.radius=on?2:1;
    this.key.shadow.bias=on?-.00025:-.0012;this.key.shadow.normalBias=on?.035:.02;
    this.setShadowSize(on&&this.tier==='high'?2048:1024);
    for(const [name,original] of this.originalMaterials){
      const m=this.mat[name];m.roughness=original.roughness;m.metalness=original.metalness;
      m.normalMap=original.normalMap;m.aoMap=original.aoMap;m.lightMap=original.lightMap;
      // ground/soft are regenerated by World.applyLevel; never restore a disposed map.
      if(name!=='ground'&&name!=='soft')m.map=original.map;
      m.needsUpdate=true;
    }
    if(on) {
      const m=this.mat;
      const bakeId=level.id==='forest'?'ground':level.id;
      m.ground.aoMap=arenaAssets[bakeId+'-ao']||null;m.ground.aoMapIntensity=.85;
      m.ground.lightMap=arenaAssets[bakeId+'-bounce']||null;m.ground.lightMapIntensity=1;
      m.ground.roughness=p.roughness;m.soft.roughness=p.crate;
      m.ground.normalMap=arenaAssets['ground-normal']||null;
      m.ground.normalScale.set(level.id==='glacier'?.08:.12,level.id==='glacier'?.08:.12);
      if(level.id==='forest') {
      if(arenaAssets.ground){if(m.ground.map!==arenaAssets.ground)m.ground.map?.dispose();m.ground.map=arenaAssets.ground;}
      if(arenaAssets.wood){if(m.soft.map!==arenaAssets.wood)m.soft.map?.dispose();m.soft.map=arenaAssets.wood;}
      m.ground.normalMap=arenaAssets['ground-normal']||null;m.ground.normalScale.set(.24,.24);
      m.ground.aoMap=arenaAssets['ground-ao']||null;m.ground.aoMapIntensity=.85;
      m.ground.lightMap=arenaAssets['ground-bounce']||null;m.ground.lightMapIntensity=1;
      m.ground.roughness=.92;m.soft.roughness=.72;
      for(const name of ['hard','hardTop','wall','wallTop']){m[name].map=arenaAssets.stone||null;m[name].roughness=.85;m[name].metalness=0;}
      m.hard.color.setHex(0xc2c7b1);m.wall.color.copy(m.hard.color);
      m.hardTop.color.setHex(0xa8bb83);m.wallTop.color.copy(m.hardTop.color);
      m.border.color.setHex(0x485340);
      }
    }
    if(!on&&this.post){this.post.dispose();this.post=null;}
  }
  setShadowSize(size){
    if(this.key.shadow.mapSize.x===size)return;
    this.key.shadow.map?.dispose();this.key.shadow.map=null;
    this.key.shadow.mapSize.set(size,size);this.key.shadow.needsUpdate=true;
  }
  geometry(w,h,d,r){return this.enabled?bevelBox(w,h,d,r):new T.BoxGeometry(w,h,d);}
  prepareFloor(geometry){if(this.enabled)geometry.setAttribute('uv1',geometry.attributes.uv.clone());}
  prepareFloors(root){
    if(!this.enabled)return;
    root.updateMatrixWorld(true);
    const inverse=root.matrixWorld.clone().invert(),matrix=new T.Matrix4(),v=new T.Vector3();
    root.traverse(mesh=>{
      if(!mesh.isMesh||mesh.material!==this.mat.ground)return;
      matrix.multiplyMatrices(inverse,mesh.matrixWorld);
      const pos=mesh.geometry.attributes.position,uv=new T.Float32BufferAttribute(new Float32Array(pos.count*2),2);
      for(let i=0;i<pos.count;i++){
        v.fromBufferAttribute(pos,i).applyMatrix4(matrix);
        uv.setXY(i,(v.x+7.5)/15,(6.5-v.z)/13);
      }
      mesh.geometry.setAttribute('uv1',uv);
    });
  }
  adapt(ms){
    if(!this.enabled||this.mode!=='auto')return;
    this.slow=ms>23?this.slow+1:0;
    if(this.slow>=2&&this.tier==='high'){
      this.tier='balanced';this.setShadowSize(1024);this.post?.dispose();this.post=null;
    }
  }
  render(scene,camera){
    if(this.enabled&&this.tier==='high'&&this.renderer.isWebGLRenderer&&this.renderer.extensions.has('EXT_color_buffer_float')){
      if(!this.post)this.post=new ArenaPost(this.renderer);
      this.post.output.uniforms.glowStrength.value=this.profile.glow;
      this.post.render(scene,camera);
    }else this.renderer.render(scene,camera);
  }
  dispose(){this.post?.dispose();for(const target of this.environments.values())target.dispose();this.environments.clear();this.post=null;this.envTarget=null;}
}
