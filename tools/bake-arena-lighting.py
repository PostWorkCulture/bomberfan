"""Bake immutable arena occlusion from the actual instanced wall layouts.
Generate layouts with BF_EXPORT_LAYOUTS=assets/lighting/layouts.json node tests/simulation-regression.mjs.
Only static wall meshes are exported. Moving maze walls, crates and actors are excluded.
"""
from pathlib import Path
import json,sys
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1];out=root/'assets/lighting'
layouts=json.loads((out/'layouts.json').read_text())
w,h=384,333; yy,xx=np.mgrid[0:h,0:w]
for name,layout in layouts.items():
 if name=='forest' or (len(sys.argv)>1 and name not in sys.argv[1:]):continue
 cols=layout.get('cols',15);rows=layout.get('rows',13)
 px=(xx+.5)/w*cols-cols/2;pz=(yy+.5)/h*rows-rows/2
 visibility=np.zeros((h,w));bounce=np.zeros((h,w,3))
 c=layout['hardColour'];colour=np.array([(c>>16)&255,(c>>8)&255,c&255])/255*.075
 for i in range(64):
  u=(i+.5)/64;phi=i*2.39996323
  dy=np.sqrt(1-u);dx=np.sqrt(u)*np.cos(phi);dz=np.sqrt(u)*np.sin(phi)
  hit=np.zeros((h,w),bool);far=min(1.10/dy,3.)
  for cx,cz in layout['hard']:
   tx0=(cx-.5-px)/(dx if abs(dx)>1e-6 else 1e-6);tx1=(cx+.5-px)/(dx if abs(dx)>1e-6 else 1e-6)
   tz0=(cz-.5-pz)/(dz if abs(dz)>1e-6 else 1e-6);tz1=(cz+.5-pz)/(dz if abs(dz)>1e-6 else 1e-6)
   enter=np.maximum(np.minimum(tx0,tx1),np.minimum(tz0,tz1));leave=np.minimum(np.maximum(tx0,tx1),np.maximum(tz0,tz1))
   hit|=(leave>np.maximum(enter,.015))&(enter<far)
  visibility+=~hit;bounce+=hit[...,None]*colour
 visibility/=64;bounce/=64
 for suffix,a in [('ao',np.repeat((.30+.70*visibility)[...,None],3,-1)),('bounce',bounce)]:
  Image.fromarray(np.uint8(np.clip(a,0,1)*255)).save(out/f'{name}-{suffix}.png',optimize=True)
 print(name,len(layout['hard']),'static occluders',flush=True)
