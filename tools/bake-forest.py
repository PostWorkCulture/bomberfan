"""Deterministic Forest textures and static ambient bake. Python, NumPy, Pillow.
Not a Blender/Cycles bake. Only immutable Forest wall cells occlude the bake.
No crate, fighter, bomb or other transient geometry is included.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
out=Path(__file__).resolve().parents[1]/'assets/forest'
out.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(7151)
def noise(n,scale):
    a=rng.integers(0,256,(scale,scale),dtype=np.uint8)
    return np.asarray(Image.fromarray(a).resize((n,n),Image.Resampling.BICUBIC),dtype=float)/255

def save(name,a):
    Image.fromarray(np.uint8(np.clip(a,0,1)*255)).save(out/(name+'.png'),optimize=True)
n=256; y,x=np.mgrid[0:n,0:n]/n
coarse=noise(n,9); fine=noise(n,90)
ground=np.stack([.19+.10*coarse,.29+.17*coarse,.105+.07*coarse],-1)
ground+=(fine[...,None]-.5)*.035
save('ground',ground)
# Fine surface normals, deliberately subdued at arena scale.
h=.7*noise(n,28)+.3*fine; dy,dx=np.gradient(h)
normal=np.stack([-dx*2,-dy*2,np.ones_like(dx)],-1)
normal/=np.linalg.norm(normal,axis=-1)[...,None]
save('ground-normal',normal*.5+.5)
wood=noise(n,7); grain=np.sin((x*62+np.sin(y*18)*.55+wood*.6)*6.28)*.025
boards=np.mod(y*4,1); seams=boards<.035
w=np.stack([.51+wood*.17+grain,.28+wood*.13+grain,.12+wood*.06+grain*.5],-1)
w[seams]*=.52
# End grain/fastenings are painted, not a mesh per crate.
for cy in [.065,.315,.565,.815]:
 for cx in [.065,.935]:
  d=((x-cx)**2+(y-cy)**2)**.5
  w[d<.014]=[.12,.10,.065]
save('wood',w)
stone=noise(n,10); pores=noise(n,90)
save('stone',np.stack([.46+stone*.13,.49+stone*.13,.40+stone*.12],-1)+(pores[...,None]-.5)*.03)
# Cosine-weighted hemisphere visibility against permanent unit wall boxes.
# Bake at 384x333. Texture v=1 is world -z (the plane's original UV convention).
w,h=384,333; yy,xx=np.mgrid[0:h,0:w]
px=(xx+.5)/w*15-7.5; pz=(yy+.5)/h*13-6.5
hard=[]
for gy in range(13):
 for gx in range(15):
  if gx in (0,14) or gy in (0,12) or (gx%2==0 and gy%2==0): hard.append((gx-7,gy-6))
visibility=np.zeros((h,w)); bounce=np.zeros((h,w,3))
for i in range(64):
 u=(i+.5)/64; phi=i*2.39996323
 dy=np.sqrt(1-u); dx=np.sqrt(u)*np.cos(phi); dz=np.sqrt(u)*np.sin(phi)
 hit=np.zeros((h,w),bool)
 # Ray can meet a wall up to wall-top height, with a three-unit AO radius.
 far=min(1.10/dy,3.)
 for cx,cz in hard:
  tx0=(cx-.5-px)/(dx if abs(dx)>1e-6 else 1e-6)
  tx1=(cx+.5-px)/(dx if abs(dx)>1e-6 else 1e-6)
  tz0=(cz-.5-pz)/(dz if abs(dz)>1e-6 else 1e-6)
  tz1=(cz+.5-pz)/(dz if abs(dz)>1e-6 else 1e-6)
  enter=np.maximum(np.minimum(tx0,tx1),np.minimum(tz0,tz1))
  leave=np.minimum(np.maximum(tx0,tx1),np.maximum(tz0,tz1))
  hit|=(leave>np.maximum(enter,.015))&(enter<far)
 visibility+=~hit
 # Small reflected green/ochre contribution from nearby stone instead of black pits.
 bounce+=hit[...,None]*np.array([.055,.070,.031])
visibility/=64; bounce/=64
save('ground-ao',np.repeat((.30+.70*visibility)[...,None],3,-1))
save('ground-bounce',bounce)
print('Baked',len(hard),'permanent cells; 64 cosine-weighted rays per texel; no destructibles.')
