import * as T from './three.module.min.js';

// Single PBR surface: GPU waves and analytic ripple normals, with no reflection
// render targets, per-frame textures or additional dynamic lights.
export function createPirateWater() {
  const time={value:0};
  const material=new T.MeshPhysicalMaterial({
    color:0x0085ce,roughness:.16,metalness:0,ior:1.333,
    clearcoat:1,clearcoatRoughness:.11,envMapIntensity:1.5,
  });
  material.userData.waterTime=time;
  material.customProgramCacheKey=()=> 'pirate-water-v1';
  material.onBeforeCompile=shader=>{
    shader.uniforms.waterTime=time;
    const wave=`
      uniform float waterTime;
      varying vec2 waterXZ;
      vec3 waveField(vec2 p){
        float a=dot(p,vec2(.85,.38))+waterTime*.78;
        float b=dot(p,vec2(-.52,1.16))-waterTime*.93;
        float c=dot(p,vec2(2.8,1.7))+waterTime*1.21;
        float d=dot(p,vec2(-3.6,2.3))-waterTime*1.53;
        return vec3(.05*sin(a)+.032*sin(b)+.012*sin(c)+.008*sin(d),
          .05*.85*cos(a)-.032*.52*cos(b)+.012*2.8*cos(c)-.008*3.6*cos(d),
          .05*.38*cos(a)+.032*1.16*cos(b)+.012*1.7*cos(c)+.008*2.3*cos(d));
      }
    `;
    shader.vertexShader=wave+shader.vertexShader;
    shader.vertexShader=shader.vertexShader.replace('#include <begin_vertex>',`
      #include <begin_vertex>
      waterXZ=vec2(position.x,-position.y);
      transformed.z+=waveField(waterXZ).x;
    `);
    shader.fragmentShader=wave+shader.fragmentShader;
    shader.fragmentShader=shader.fragmentShader.replace('#include <clearcoat_normal_fragment_maps>', '#include <clearcoat_normal_fragment_maps>\n#ifdef USE_CLEARCOAT\nclearcoatNormal=normal;\n#endif');
    shader.fragmentShader=shader.fragmentShader.replace('#include <normal_fragment_maps>',`
      #include <normal_fragment_maps>
      vec3 field=waveField(waterXZ);
      vec2 fine=waterXZ*4.0+vec2(sin(waterXZ.y*1.7+waterTime*.35),cos(waterXZ.x*1.5-waterTime*.4))*.48;
      vec2 ripple=vec2(cos(fine.x+fine.y*.7+waterTime),sin(fine.y-fine.x*.55-waterTime*.8))*.055;
      vec3 waterNormal=normalize(vec3(-field.y*2.4-ripple.x,1.0,-field.z*2.4-ripple.y));
      normal=normalize(mat3(viewMatrix)*waterNormal);
      float ribbons=pow(max(0.0,1.0-abs(sin(fine.x+sin(fine.y))*cos(fine.y*.83+sin(fine.x*.72)))),12.0);
      diffuseColor.rgb=mix(diffuseColor.rgb*vec3(.55,.78,.96),diffuseColor.rgb*vec3(.75,1.14,1.2),.5+.5*sin(fine.y*.4+field.x*6.0));
      diffuseColor.rgb+=vec3(.008,.065,.105)*ribbons;
    `);
  };
  return material;
}
