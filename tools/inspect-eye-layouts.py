"""Inspect source glTF eye islands in true Head bind coordinates (offline QA)."""
import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]

def inspect(name):
    path = ROOT / 'assets/characters' / (name + '.gltf')
    g = json.loads(path.read_text())
    buf = (path.parent / g['buffers'][0]['uri']).read_bytes()
    def acc(i):
        a = g['accessors'][i]; v = g['bufferViews'][a['bufferView']]
        dtype = {5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1'}[a['componentType']]
        n = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        return np.ndarray((a['count'],n), dtype=dtype, buffer=buf,
            offset=v.get('byteOffset',0)+a.get('byteOffset',0),
            strides=(v.get('byteStride',np.dtype(dtype).itemsize*n),np.dtype(dtype).itemsize)).copy()
    skin = g['skins'][0]
    head = next(i for i,n in enumerate(g['nodes']) if n.get('name')=='Head')
    inverse = acc(skin['inverseBindMatrices'])[skin['joints'].index(head)].reshape(4,4).T
    result = []
    for mi, mesh in enumerate(g['meshes']):
        prim = mesh['primitives'][0]; a = prim['attributes']
        pos = acc(a['POSITION']); uv = acc(a['TEXCOORD_0'])
        hp = (np.c_[pos,np.ones(len(pos))] @ inverse.T)[:,:3]
        indices = acc(prim['indices']).flatten().reshape(-1,3)
        parent = list(range(len(pos)))
        def find(i):
            while parent[i]!=i:
                parent[i]=parent[parent[i]]; i=parent[i]
            return i
        def union(a,b): parent[find(a)] = find(b)
        for tri in indices:
            union(int(tri[0]),int(tri[1])); union(int(tri[1]),int(tri[2]))
        # Weld duplicated UV seam vertices within their palette island.
        seen = {}
        for i,p in enumerate(pos):
            key = (*np.round(p,5),round(float(uv[i,0]),4))
            if key in seen: union(i,seen[key])
            else: seen[key]=i
        components = {}
        for i in range(len(pos)): components.setdefault(find(i),[]).append(i)
        eye_u = (0.008,0.027) if name=='frog' else (0.03,0.065)
        pupil_u = (0.03,0.065) if name=='frog' else (0.008,0.027)
        globes = [ids for ids in components.values() if 150<=len(ids)<=230
            and eye_u[0]<uv[ids[0],0]<eye_u[1]]
        pupils = [ids for ids in components.values() if 18<=len(ids)<=50
            and pupil_u[0]<uv[ids[0],0]<pupil_u[1]]
        eyes = []; removed = []
        for ids in sorted(globes,key=lambda ids:hp[ids,0].mean()):
            q=hp[ids]; centre=(q.min(0)+q.max(0))/2
            if not pupils: continue
            pid=min(pupils,key=lambda p:np.linalg.norm(hp[p].mean(0)-centre))
            normal=hp[pid].mean(0)-centre; normal/=np.linalg.norm(normal)
            right=inverse[:3,:3]@np.array([1.,0.,0.]); right-=normal*np.dot(right,normal); right/=np.linalg.norm(right)
            up=np.cross(normal,right); up/=np.linalg.norm(up)
            axes=np.array([right,up,normal]).T
            radii=np.max(np.abs((q-centre)@axes),axis=0)
            if radii.max()/radii.min()>1.5 or np.linalg.norm(hp[pid].mean(0)-centre)>radii.max()*1.4:
                continue
            eyes.append({'center':centre.round(5).tolist(),'right':right.round(5).tolist(),
                'up':up.round(5).tolist(),'normal':normal.round(5).tolist(),'radii':radii.round(5).tolist()})
            removed+=ids+pid
        if eyes:
            ranges=[]
            for i in sorted(set(removed)):
                if ranges and i==ranges[-1][1]+1: ranges[-1][1]=i
                else:ranges.append([i,i])
            node=next(n for n in g['nodes'] if n.get('mesh')==mi)
            result.append({'mesh':node['name'],'ranges':ranges,'eyes':eyes})
    return result

if __name__=='__main__':
    layouts={}
    for p in sorted((ROOT/'assets/characters').glob('*.gltf')):
        if p.stem in ['birb','blue-demon']:continue
        layouts[p.stem]=inspect(p.stem)
    print(json.dumps(layouts,indent=2))
