import fs from 'node:fs';
import {createRequire} from 'node:module';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as T from '../assets/vendor/three.module.min.js';
import {EYE_STYLES} from '../assets/vendor/roster-eyes.js';
const modules=process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES||'/opt/codex/runtimes/codex-primary-runtime/dependencies/node/node_modules';
const require=createRequire(path.join(modules,'package.json'));
const {createCanvas}=require('@napi-rs/canvas');
const textureCache=new Map();
const eyeGeometry=new T.SphereGeometry(1,20,12);
const rgb=hex=>[(hex>>16)&255,(hex>>8)&255,hex&255];
const mix=(a,b,t)=>a.map((v,i)=>v+(b[i]-v)*Math.max(0,Math.min(1,t)));
function eyeTexture(id,style,side){
  const key=id+':'+side;
  if(textureCache.has(key))return textureCache.get(key);
  const canvas=createCanvas(256,128);
  const ctx=canvas.getContext('2d'),image=ctx.createImageData(canvas.width,canvas.height);
  const white=rgb(style.white||0xfff2e5),iris=rgb(Array.isArray(style.iris)?style.iris[side]:style.iris);
  const lid=rgb(style.lidColor),ink=[6,10,17],shine=style.shine||1;
  const cut=Array.isArray(style.lid)?style.lid[side]:style.lid;
  const gaze=side===0?.055:-.055;
  for(let py=0;py<canvas.height;py++)for(let px=0;px<canvas.width;px++){
    // SphereGeometry UV convention; CanvasTexture flips Y on upload.
    const u=(px+.5)/canvas.width,v=1-(py+.5)/canvas.height;
    const theta=(1-v)*Math.PI,phi=u*Math.PI*2;
    const x=-Math.cos(phi)*Math.sin(theta),y=Math.cos(theta),z=Math.sin(phi)*Math.sin(theta);
    let c=white;
    if(z>0){
      const dx=x-gaze,dist=Math.hypot(dx,y),radius=style.size;
      const ring=1-T.MathUtils.smoothstep(dist,radius+.026,radius+.059);
      c=mix(c,ink,ring);
      const angle=Math.atan2(y,dx),r=dist/radius;
      const fibres=(Math.sin(angle*31+r*8)+Math.sin(angle*53-r*12))*.035;
      let tint=mix(iris,[255,221,141],Math.max(0,1-r)*.28+fibres);
      tint=mix(tint,ink,T.MathUtils.smoothstep(r,.82,1)*.25);
      c=mix(c,tint,1-T.MathUtils.smoothstep(dist,radius-.018,radius+.009));
      const pupil=Math.hypot(dx/style.pupil[0],y/style.pupil[1]);
      c=mix(c,ink,1-T.MathUtils.smoothstep(pupil,.93,1.035));
      const spark=Math.hypot((dx+.18*shine)/(.105*shine),(y-.24*shine)/(.115*shine));
      c=mix(c,[255,255,255],1-T.MathUtils.smoothstep(spark,.75,1.16));
      const small=Math.hypot((dx-.14*shine)/(.039*shine),(y+.18*shine)/(.045*shine));
      c=mix(c,[161,215,226],(1-T.MathUtils.smoothstep(small,.65,1.20))*.85);
      if(cut<.94){
        const edge=cut+(style.slant||0)*x*(side===0?-1:1);
        const crease=T.MathUtils.smoothstep(y,edge-.025,edge+.013);
        c=mix(c,mix(lid,ink,.35),crease);
        c=mix(c,lid,T.MathUtils.smoothstep(y,edge+.012,edge+.072));
      }
    }
    const index=(py*canvas.width+px)*4;
    image.data[index]=c[0];image.data[index+1]=c[1];image.data[index+2]=c[2];image.data[index+3]=255;
  }
  ctx.putImageData(image,0,0);
  const texture=new T.CanvasTexture(canvas);texture.colorSpace=T.SRGBColorSpace;
  texture.anisotropy=4;texture.userData.sharedEyeTexture=true;
  textureCache.set(key,texture);return texture;
}


const atlas=createCanvas(1560,792),ctx=atlas.getContext('2d');
let i=0;for(const [id,style] of Object.entries(EYE_STYLES))for(const side of [0,1]){
 const tile=eyeTexture(id,style,side).image,x=(i%6)*260,y=Math.floor(i/6)*132;i++;
 ctx.drawImage(tile,x+2,y+2);
 ctx.drawImage(tile,0,0,1,128,x,y+2,2,128);ctx.drawImage(tile,255,0,1,128,x+258,y+2,2,128);
 ctx.drawImage(tile,0,0,256,1,x+2,y,256,2);ctx.drawImage(tile,0,127,256,1,x+2,y+130,256,2);
}
const output=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../assets/characters/roster-eye-atlas.png');
fs.writeFileSync(output,atlas.toBuffer('image/png'));console.log('Generated 36 eye surfaces:',output);
