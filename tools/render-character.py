"""Render exported posed geometry for art QA. CPU studio lighting, not WebGL."""
import argparse, json, math, base64, io
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import numpy as np
from PIL import Image, ImageDraw, ImageFont

def unit(v):
    v=np.asarray(v,dtype=float)
    return v/np.maximum(np.linalg.norm(v,axis=-1,keepdims=True),1e-9)

def stage(bounds):
    lo,hi=np.array(bounds['min']),np.array(bounds['max']); h=hi[1]-lo[1]
    center=np.array([(lo[0]+hi[0])/2,lo[1]-.006,(lo[2]+hi[2])/2])
    result=[]
    for inner,outer,color,dy in [(0,h*2,[.42,.44,.47],-.015),(0,h*.43,[.32,.35,.38],0),(h*.30,h*.34,[.07,.43,.48],.002)]:
        positions=[];indices=[]
        for k in range(65):
            a=k/64*math.tau
            for r in [inner,outer]:positions.append((center+np.array([math.cos(a)*r,dy,math.sin(a)*r])).tolist())
            if k:indices.extend([2*k-2,2*k,2*k-1,2*k-1,2*k,2*k+1])
        result.append(dict(positions=np.array(positions).ravel().tolist(),normals=[0,1,0]*len(positions),colors=color*len(positions),indices=indices,material={'roughness':.9}))
    return result

def render(variant,yaw=0,pitch=8,face=False,size=320,portrait=False,framing=None):
    framing=framing or variant
    lo=np.array(framing['bounds']['min']);hi=np.array(framing['bounds']['max']);span=hi-lo
    target=(lo+hi)/2
    if face:
        eye_meshes=[m for m in framing['meshes'] if m['name'].startswith('Eye')]
        if eye_meshes:
            p=np.concatenate([np.array(m['positions']).reshape(-1,3) for m in eye_meshes])
            target=(p.min(0)+p.max(0))/2;target[1]-=span[1]*.03
        else:target[1]=lo[1]+span[1]*.73
        height=span[1]*.55
    else:height=max(span[1],span[0]*.88)*1.20
    fov=math.radians(32);distance=height/(2*math.tan(fov/2))
    y,p=math.radians(yaw),math.radians(pitch)
    eye=target+distance*np.array([math.sin(y)*math.cos(p),math.sin(p),math.cos(y)*math.cos(p)])
    backward=unit(eye-target);right=unit(np.cross([0,1,0],backward));up=np.cross(backward,right)
    basis=np.array([right,up,backward]).T
    yy,xx=np.mgrid[0:size,0:size];rad=((xx-size*.5)/size)**2+((yy-size*.44)/size)**2
    bg=np.array([.011,.020,.045])+(1-np.clip(rad*2,0,1))[...,None]*np.array([.013,.021,.042])
    color=bg.copy();depth=np.full((size,size),np.inf)
    focal=size/(2*math.tan(fov/2))
    lights=[(unit([-3,6,7]),.90),(unit([4,2,3]),.32),(unit([1,4,-5]),.42)]
    meshes=variant['meshes']+(stage(variant['bounds']) if portrait else [])
    for mesh in meshes:
        pos=np.asarray(mesh['positions']).reshape(-1,3);norm=np.asarray(mesh['normals']).reshape(-1,3)
        cols=np.asarray(mesh['colors']).reshape(-1,3)
        texture=None
        if mesh.get('texturePNG'):
            texture=np.asarray(Image.open(io.BytesIO(base64.b64decode(mesh['texturePNG']))).convert('RGB'),dtype=float)/255
            texture=np.where(texture<=.04045,texture/12.92,((texture+.055)/1.055)**2.4)
            uvs=np.asarray(mesh['uvs']).reshape(-1,2)
        emission=np.asarray(mesh.get('emissiveColors',np.zeros_like(pos))).reshape(-1,3)
        if 'emissiveColors' not in mesh:
            emission[:]=np.array(mesh['material'].get('emissive',[0,0,0]))*mesh['material'].get('emissiveIntensity',0)
        cam=(pos-eye)@basis;z=-cam[:,2]
        screen=np.c_[size/2+cam[:,0]/np.maximum(z,1e-6)*focal,size/2-cam[:,1]/np.maximum(z,1e-6)*focal]
        rough=mesh['material'].get('roughness',.5);shine=max(8,(1-rough)*110)
        for tri in np.asarray(mesh['indices']).reshape(-1,3):
            if np.any(z[tri]<=0):continue
            xy=screen[tri];mn=np.maximum(np.floor(xy.min(0)).astype(int),0);mx=np.minimum(np.ceil(xy.max(0)).astype(int),size-1)
            if np.any(mx<mn):continue
            a,b,c=xy;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-7:continue
            py,px=np.mgrid[mn[1]:mx[1]+1,mn[0]:mx[0]+1];px=px+.5;py=py+.5
            w0=((b[1]-c[1])*(px-c[0])+(c[0]-b[0])*(py-c[1]))/den
            w1=((c[1]-a[1])*(px-c[0])+(a[0]-c[0])*(py-c[1]))/den
            weights=np.stack([w0,w1,1-w0-w1],-1)
            mask=np.all(weights>=-1e-6,axis=-1)
            reciprocal=np.sum(weights/z[tri],axis=-1);zz=1/np.maximum(reciprocal,1e-8)
            region=np.s_[mn[1]:mx[1]+1,mn[0]:mx[0]+1]
            mask &= zz<depth[region]
            if not np.any(mask):continue
            w=weights[mask]/z[tri];w/=w.sum(-1,keepdims=True)
            normals=unit(w@norm[tri]);points=w@pos[tri];view=unit(eye-points)
            light=np.full((len(w),1),.25);spec=np.zeros((len(w),1))
            for direction,power in lights:
                light+=np.maximum(0,normals@direction)[:,None]*power
                half=unit(view+direction)
                spec+=np.maximum(0,np.sum(normals*half,axis=1))[:,None]**shine*power*(1-rough)*.2
            base=w@cols[tri];emit=w@emission[tri]
            if texture is not None:
                uv=w@uvs[tri]
                if mesh.get('textureFlipY',True):uv[:,1]=1-uv[:,1]
                tx=np.clip(uv[:,0]*(texture.shape[1]-1),0,texture.shape[1]-1);ty=np.clip(uv[:,1]*(texture.shape[0]-1),0,texture.shape[0]-1)
                ix=tx.astype(int);iy=ty.astype(int);fx=(tx-ix)[:,None];fy=(ty-iy)[:,None]
                jx=np.minimum(ix+1,texture.shape[1]-1);jy=np.minimum(iy+1,texture.shape[0]-1)
                tex=(texture[iy,ix]*(1-fx)+texture[iy,jx]*fx)*(1-fy)+(texture[jy,ix]*(1-fx)+texture[jy,jx]*fx)*fy
                base*=tex
                if mesh.get('textureEmissive'):emit*=tex
            shaded=base*light+spec+emit
            color[region][mask]=shaded;depth[region][mask]=zz[mask]
    # ACES-like display transform, followed by linear sRGB to display sRGB.
    color=np.clip((color*(2.51*color+.03))/(color*(2.43*color+.59)+.14),0,1)
    color=np.where(color<=.0031308,color*12.92,1.055*color**(1/2.4)-.055)
    return Image.fromarray(np.uint8(np.clip(color,0,1)*255))

def one(job):
    path,out,size=job;doc=json.loads(Path(path).read_text());name=Path(path).stem;out=Path(out)
    for variant in ['before','after']:
        model=doc['variants'][variant]
        for view,yaw,pitch,face in [('front',0,8,False),('face',0,6,True),('quarter',-28,10,False),('gameplay',25,48,False)]:
            render(model,yaw,pitch,face,size,framing=doc['variants']['after']).save(out/f'{name}-{variant}-{view}.png')
        if variant=='after':
            render(model,-13,8,False,640,True).resize((320,320),Image.Resampling.LANCZOS).save(out/f'{name}-portrait.webp',quality=95)
    return name,doc['metadata']

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('input');parser.add_argument('--out',required=True);parser.add_argument('--size',type=int,default=320);parser.add_argument('--workers',type=int,default=3)
    args=parser.parse_args();out=Path(args.out);out.mkdir(parents=True,exist_ok=True)
    paths=sorted(Path(args.input).glob('*.json')) if Path(args.input).is_dir() else [Path(args.input)]
    with ProcessPoolExecutor(max_workers=args.workers) as pool:results=list(pool.map(one,[(p,out,args.size) for p in paths]))
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',16)
    for variant,view in [('before','face'),('after','face'),('after','quarter'),('after','gameplay')]:
        sheet=Image.new('RGB',(6*240,math.ceil(len(results)/6)*280+54),(13,19,32));draw=ImageDraw.Draw(sheet)
        draw.text((18,16),f'ROSTER EYE REVIEW / {variant.upper()} {view.upper()} / Actual model geometry, CPU studio lighting',font=font,fill='white')
        for i,(name,metadata) in enumerate(results):
            x=(i%6)*240;y=(i//6)*280+54
            sheet.paste(Image.open(out/f'{name}-{variant}-{view}.png').resize((236,236)),(x,y))
            draw.text((x+8,y+238),metadata['name'],font=font,fill='white')
        sheet.save(out/f'roster-{variant}-{view}.png')
    print(json.dumps({'rendered':len(results),'output':str(out),'scope':'CPU geometry studio renders; not WebGL captures'}))
