// Surface treatments preserve the original UV artwork, eyes and animated rigs.
// One bounded particle draw per fighter; no lights, textures or per-frame allocations.
const LOOKS = {
  tribal: { skin: 0xc56435, glow: 0xff793a, label: 'Ritual embers' },
  bunny: { skin: 0xa07fba, glow: 0xb20d2b, label: 'Blood drips' },
  'skull-orc': { skin: 0xb87a36, glow: 0xffc768, label: 'Bonefire sparks' },
  'evolved-dragon': { skin: 0x4379c4, glow: 0xff6327, label: 'Dragon cinders' },
  orc: { skin: 0xb32c48, glow: 0xf04478, label: 'Crimson ash' },
  hulk: { skin: 0x568e32, glow: 0x80ea46, label: 'Gamma shimmer' },
};

export function finishMaterial(T, material, def) {
  const look = LOOKS[def.id];
  if (!look || def.id === 'hulk') return;
  const time = { value: 0 };
  material.userData.finishTime = time;
  const blood = def.id === 'bunny';
  material.onBeforeCompile = shader => {
    shader.uniforms.fighterTime = time;
    shader.uniforms.fighterSkin = { value: new T.Color(look.skin) };
    shader.uniforms.fighterAccent = { value: new T.Color(look.glow) };
    shader.vertexShader = 'varying vec3 fighterRest;\n' + shader.vertexShader;
    shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>',
      '#include <begin_vertex>\nfighterRest = position;');
    shader.fragmentShader = `uniform float fighterTime;
uniform vec3 fighterSkin;
uniform vec3 fighterAccent;
varying vec3 fighterRest;
float bloodRun(vec3 p, float x, float start, float span, float phase) {
  float tip = start - span * (.83 + .17 * sin(fighterTime * 1.4 + phase));
  float bend = .012 * sin(p.y * 19.0 + phase);
  float width = .018 + .018 * smoothstep(tip, start, p.y);
  float line = 1.0 - smoothstep(width, width + .008, abs(p.x - x - bend));
  float ends = smoothstep(tip - .02, tip + .025, p.y) * (1.0 - smoothstep(start, start + .06, p.y));
  float bead = 1.0 - smoothstep(.02, .034, length(vec2(p.x - x - bend, (p.y - tip) * .7)));
  return max(line * ends, bead);
}
` + shader.fragmentShader;
    shader.fragmentShader = shader.fragmentShader.replace('#include <map_fragment>', `
#include <map_fragment>
// Select green/yellow-green pigment, not neutral bone, teeth or dark linework.
vec3 originalPigment = diffuseColor.rgb;
float greenMask = smoothstep(.012, .065, originalPigment.g - originalPigment.b)
  * smoothstep(.0, .05, originalPigment.g - originalPigment.r * .86);
float pigmentValue = max(max(originalPigment.r, originalPigment.g), originalPigment.b);
diffuseColor.rgb = mix(originalPigment, fighterSkin * (.32 + pigmentValue * 1.55), greenMask);
float fighterBlood = 0.0;
${blood ? `
vec3 bp = fighterRest;
// Rest-space stains deform with the skin, never float above the face.
fighterBlood = max(bloodRun(bp, -.22, 1.88, .82, .4), bloodRun(bp, .14, 1.87, .64, 2.0));
fighterBlood = max(fighterBlood, bloodRun(bp, .46, 1.58, .52, 3.8));
fighterBlood = max(fighterBlood, bloodRun(bp, -.48, 1.55, .43, 1.3));
fighterBlood *= smoothstep(-.38, -.12, bp.z) * (1.0 - smoothstep(1.92, 1.98, bp.y));
vec3 wetRed = mix(vec3(.15,.002,.009), vec3(.45,.006,.025), .5 + .5*sin(bp.y*31.0));
diffuseColor.rgb = mix(diffuseColor.rgb, wetRed, fighterBlood * .96);
` : ''}
`);
    if (blood) shader.fragmentShader = shader.fragmentShader.replace('#include <roughnessmap_fragment>',
      '#include <roughnessmap_fragment>\nroughnessFactor = mix(roughnessFactor, .19, fighterBlood);');
    else shader.fragmentShader = shader.fragmentShader.replace('#include <emissivemap_fragment>',
      '#include <emissivemap_fragment>\ntotalEmissiveRadiance += fighterAccent * pow(1.0 - clamp(dot(normal, normalize(vViewPosition)), 0.0, 1.0), 3.0) * .085;');
  };
  material.customProgramCacheKey = () => 'fighter-finish-v1-' + def.id;
  material.needsUpdate = true;
}

export function addSignatureEffect(T, group, def) {
  const look = LOOKS[def.id];
  if (!look) return;
  const blood = def.id === 'bunny', count = blood ? 7 : 16;
  const geometry = new T.BufferGeometry();
  const positions = new Float32Array(count * 3), seeds = new Float32Array(count);
  for (let i=0; i<count; i++) seeds[i] = (i + .5) / count;
  geometry.setAttribute('position', new T.BufferAttribute(positions, 3));
  geometry.setAttribute('seed', new T.BufferAttribute(seeds, 1));
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const material = new T.ShaderMaterial({
    uniforms: { tint: {value:new T.Color(look.glow)}, blood: {value:blood ? 1 : 0} },
    vertexShader: `attribute float seed; varying float fade; uniform float blood;
      void main(){ vec4 p=modelViewMatrix*vec4(position,1.0);gl_Position=projectionMatrix*p;
        gl_PointSize=clamp((blood>.5?10.0:9.0)/max(.5,-p.z),1.5,11.0);
        fade=.35+.65*seed; }`,
    fragmentShader: `uniform vec3 tint; uniform float blood; varying float fade;
      void main(){ vec2 p=gl_PointCoord-.5; p.x*=mix(1.0,1.65,blood);
        float a=1.0-smoothstep(.12,.48,length(p));if(a<.015)discard;
        gl_FragColor=vec4(tint,a*fade*mix(.58,.92,blood)); }`,
    transparent:true, depthWrite:false, toneMapped:false,
    blending: blood ? T.NormalBlending : T.AdditiveBlending,
  });
  const particles = new T.Points(geometry, material);
  particles.name = 'SignatureEffect'; particles.frustumCulled = false;
  particles.userData.signatureEffect = look.label;
  group.add(particles);
  const clocks = [];
  group.traverse(o => {
    const materials = o.material ? (Array.isArray(o.material) ? o.material : [o.material]) : [];
    materials.forEach(m => { if(m.userData.finishTime) clocks.push(m.userData.finishTime); });
  });
  const update = t => {
    if(reduced) t=1.2;
    clocks.forEach(clock => {clock.value=t;});
    for(let i=0;i<count;i++) {
      const seed=seeds[i], phase=(t*(blood?.29:.18)+seed)%1;
      const angle=seed*39.6+t*.26, radius=.23+seed*.14;
      positions[i*3]=blood ? (i%2 ? -.045 : .034)+Math.sin(i*2.1)*.025 : Math.cos(angle)*radius;
      positions[i*3+1]=blood ? .48-phase*.44 : .045+phase*.68;
      positions[i*3+2]=blood ? .125+seed*.028 : Math.sin(angle)*radius;
      if(def.id==='tribal') {
        positions[i*3]=Math.cos(angle+phase*5)*radius;
        positions[i*3+2]=Math.sin(angle+phase*5)*radius;
      } else if(def.id==='evolved-dragon') {
        positions[i*3]*=1.25;
        positions[i*3+1]=.16+phase*.55;
      } else if(def.id==='orc') {
        positions[i*3+1]=.72-phase*.62;
        positions[i*3]+=Math.sin(phase*6+seed)*.06;
      } else if(def.id==='hulk') {
        positions[i*3]=(i%2?1:-1)*(.24+Math.sin(angle)*.055);
        positions[i*3+1]=.3+Math.cos(angle)*.12;
        positions[i*3+2]=.13+Math.sin(angle)*.075;
      }
    }
    geometry.attributes.position.needsUpdate=true;
  };
  (group.userData.cosAnim ||= []).push(update);
  group.userData.signatureEffect=look.label;
  group.userData.effectParticleCount=count;
  update(1.2);
}
