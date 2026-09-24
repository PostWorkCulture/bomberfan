// Code-native articulated Hulk. All visible parts belong to this model; no
// replacement face is layered onto an existing character or texture.
export function createHulk(T) {
  const root = new T.Group(), model = new T.Group();
  root.add(model);
  const material = (color, roughness = .72) => new T.MeshStandardMaterial({color, roughness, metalness:0});
  const skin = material(0x568e32), lightSkin = material(0x649f3c), darkSkin = material(0x355d26);
  const cloth = material(0x40304f, .94), seam = material(0x2a2037), hair = material(0x152318, .92);
  const cavity = material(0x1b1116), tongue = material(0x812e42), ivory = material(0xeee6bc), iris = material(0xa4bc63);
  const unit = new T.SphereGeometry(1, 20, 14);
  function part(name, mat, xyz, scale, parent=model, geometry=unit) {
    const mesh = new T.Mesh(geometry,mat); mesh.name=name;
    mesh.position.set(...xyz);mesh.scale.set(...scale);
    mesh.castShadow=mesh.receiveShadow=true;parent.add(mesh);return mesh;
  }
  function joint(name, xyz, parent=model) {const g=new T.Group();g.name=name;g.position.set(...xyz);parent.add(g);return g;}
  function tube(name, points, radius, mat, parent=model) {
    const curve=new T.CatmullRomCurve3(points.map(p=>new T.Vector3(...p)));
    return part(name,mat,[0,0,0],[1,1,1],parent,new T.TubeGeometry(curve,12,radius,5,false));
  }
  function muscle(name, sections, parent) {
    const verts=[],faces=[],n=24;
    sections.forEach(([y,x,rx,rz,z=0],r)=>{
      for(let j=0;j<=n;j++){
        const a=j/n*Math.PI*2;
        verts.push(x+Math.sin(a)*rx,y,z+Math.cos(a)*rz);
        if(r<sections.length-1&&j<n){const k=r*(n+1)+j;faces.push(k,k+n+1,k+1,k+1,k+n+1,k+n+2);}
      }
    });
    const geometry=new T.BufferGeometry();geometry.setAttribute('position',new T.Float32BufferAttribute(verts,3));
    geometry.setIndex(faces);geometry.computeVertexNormals();
    return part(name,skin,[0,0,0],[1,1,1],parent,geometry);
  }
  // A continuous tapered torso, with sculpted pectoral/abdominal relief in
  // the surface itself. Elliptical sections keep a broad back and narrow waist.
  const rings=[[.78,.34,.22],[.94,.36,.24],[1.12,.40,.25],[1.3,.49,.28],
    [1.48,.58,.31],[1.64,.56,.27],[1.73,.39,.22],[1.8,.20,.17]];
  const positions=[],uvs=[],indices=[],segments=40;
  for(let r=0;r<rings.length;r++)for(let j=0;j<=segments;j++) {
    const [y,rx,rz]=rings[r],a=j/segments*Math.PI*2,x=Math.sin(a)*rx;
    const front=Math.max(0,Math.cos(a));
    const pec=Math.exp(-Math.pow((y-1.48)/.20,2))*.045*Math.sin(Math.abs(x)/.6*Math.PI);
    const abs=Math.exp(-Math.pow((y-1.1)/.22,2))*.018*Math.cos(x*12);
    positions.push(x,y,Math.cos(a)*rz+front*(pec+abs));uvs.push(j/segments,r/(rings.length-1));
    if(r<rings.length-1&&j<segments){const k=r*(segments+1)+j;indices.push(k,k+1,k+segments+1,k+1,k+segments+2,k+segments+1);}
  }
  const torsoGeo=new T.BufferGeometry();torsoGeo.setAttribute('position',new T.Float32BufferAttribute(positions,3));
  torsoGeo.setAttribute('uv',new T.Float32BufferAttribute(uvs,2));torsoGeo.setIndex(indices);torsoGeo.computeVertexNormals();
  const torso=part('Sculpted torso',skin,[0,0,0],[1,1,1],model,torsoGeo);
  part('Trapezius',skin,[0,1.72,-.01],[.38,.16,.24]);
  part('Neck',skin,[0,1.84,0],[.20,.24,.18]);
  // Subtle anatomical folds, kept close to the surface instead of black lines.
  tube('Sternum',[[0,1.61,.306],[0,1.48,.33],[0,1.34,.294]],.009,darkSkin);
  for(const side of [-1,1]) {
    tube('Pectoral fold',[[side*.035,1.34,.288],[side*.23,1.31,.273],[side*.43,1.35,.19]],.009,darkSkin);
    part('Abdominal plane',skin,[side*.10,1.16,.23],[.105,.11,.037]);
    part('Lower abdominal plane',skin,[side*.09,.99,.224],[.09,.08,.028]);
  }
  const hips=part('Shorts waist',cloth,[0,.81,0],[.38,.20,.26]);
  tube('Waistband',[[-.31,.88,.15],[0,.905,.259],[.31,.88,.15]],.021,seam);
  tube('Fly seam',[[0,.85,.265],[0,.73,.276],[.035,.63,.244]],.009,seam);
  const legs=[],arms=[];
  for(const side of [-1,1]) {
    const leg=joint(side<0?'Left leg':'Right leg',[side*.225,.71,0]);legs.push({leg,side});
    part('Muscular thigh',skin,[0,-.18,.0],[.22,.31,.22],leg);
    part('Shorts leg',cloth,[0,-.035,.012],[.236,.19,.25],leg);
    // Irregular cloth triangles make a genuine torn hem with open green gaps.
    for(let j=0;j<9;j++) {
      const a=j/9*Math.PI*2;
      const flap=part('Torn cloth hem',cloth,[Math.sin(a)*.19,-.19-(j%3)*.015,Math.cos(a)*.20+.012],
        [.065,.11+(j%3)*.018,.035],leg,new T.ConeGeometry(1,1,3));flap.rotation.z=Math.PI;
    }
    part('Knee',lightSkin,[0,-.385,.07],[.155,.135,.175],leg);
    part('Calf',skin,[side*.015,-.49,-.015],[.17,.24,.17],leg);
    part('Bare foot',skin,[side*.018,-.65,.10],[.205,.10,.285],leg);
    for(let j=0;j<5;j++) {
      const x=side*(.135-j*.065),length=.095-j*.009;
      part('Toe',skin,[x,-.657,.326-j*.008],[.040,.062,length],leg);
      part('Toenail',darkSkin,[x,-.618,.363-j*.01],[.026,.008,.028],leg);
    }
    const arm=joint(side<0?'Left arm':'Right arm',[side*.52,1.60,0]);arm.rotation.z=side*.16;
    muscle('Continuous shoulder and upper arm',[
      [.20,side*.03,.03,.04],[.13,side*.065,.20,.18],
      [0,side*.085,.265,.24],[-.15,side*.105,.23,.235],
      [-.28,side*.12,.225,.225,.025],[-.39,side*.13,.18,.17,.02],
      [-.52,side*.13,.135,.135,.035],
    ],arm);
    const forearm=joint('Elbow',[side*.13,-.49,.035],arm);forearm.rotation.x=-.20;
    part('Forearm',skin,[0,-.17,.02],[.20,.25,.195],forearm);
    part('Wrist',skin,[0,-.34,.07],[.14,.13,.14],forearm);
    const fist=joint('Hand',[0,-.43,.11],forearm);
    part('Palm',skin,[0,0,0],[.215,.18,.155],fist);
    for(let j=0;j<4;j++) {
      const x=-.145+j*.092;
      part('Finger',skin,[x,-.09,.11],[.06,.10,.07],fist);
      part('Knuckle',lightSkin,[x,.028,.127],[.057,.068,.048],fist);
      tube('Finger crease',[[x-.033,-.054,.164],[x,-.057,.181],[x+.033,-.054,.164]],.006,darkSkin,fist);
    }
    const thumb=part('Thumb',skin,[-side*.19,-.02,.10],[.08,.135,.085],fist);thumb.rotation.z=side*.5;
    tube('Forearm tendon',[[-.07,-.06,.187],[-.045,-.19,.205],[-.02,-.32,.15]],.012,lightSkin,forearm);
    arms.push({arm,forearm,side});
  }
  const head=joint('Head',[0,1.96,.015]);
  // Squared continuous head and heavy lower jaw, matching the reference's
  // compact forehead and broad chin rather than a round toy head.
  const skullGeo=unit.clone();const p=skullGeo.attributes.position;
  for(let i=0;i<p.count;i++){const x=p.getX(i),y=p.getY(i),z=p.getZ(i);p.setXYZ(i,Math.sign(x)*Math.pow(Math.abs(x),.72),y,Math.sign(z)*Math.pow(Math.abs(z),.8));}skullGeo.computeVertexNormals();
  part('Skull',skin,[0,.10,0],[.255,.32,.245],head,skullGeo);
  part('Heavy jaw',skin,[0,-.085,.105],[.248,.155,.224],head,skullGeo);
  part('Chin',lightSkin,[0,-.16,.17],[.18,.072,.17],head);
  part('Open mouth',cavity,[0,-.055,.305],[.145,.112,.045],head);
  part('Tongue',tongue,[0,-.117,.335],[.084,.03,.018],head);
  for(let j=0;j<6;j++)part('Upper tooth',ivory,[-.104+j*.041,.016,.339],[.022,.032,.014],head);
  for(let j=0;j<5;j++)part('Lower tooth',ivory,[-.078+j*.039,-.132,.333],[.020,.016,.013],head);
  for(const side of [-1,1]) {
    part('Cheekbone',skin,[side*.175,.018,.19],[.10,.105,.11],head);
    part('Recessed eye socket',darkSkin,[side*.098,.17,.226],[.09,.061,.026],head);
    part('Eye',ivory,[side*.098,.161,.247],[.054,.023,.012],head);
    part('Iris',iris,[side*.086,.16,.259],[.018,.02,.006],head);
    part('Pupil',hair,[side*.086,.16,.265],[.008,.014,.004],head);
    const brow=part('Heavy brow ridge',skin,[side*.10,.209,.237],[.112,.041,.052],head);brow.rotation.z=side*.23;
    const ear=part('Ear',skin,[side*.264,.11,-.01],[.068,.11,.057],head);ear.rotation.z=-side*.16;
    part('Ear fold',darkSkin,[side*.282,.112,.035],[.029,.052,.012],head);
    tube('Snarl crease',[[side*.065,.059,.288],[side*.13,.018,.285],[side*.17,-.065,.27]],.008,darkSkin,head);
  }
  part('Nose bridge',skin,[0,.13,.252],[.053,.083,.066],head);
  part('Nose tip',lightSkin,[0,.068,.302],[.067,.041,.047],head);
  for(const side of [-1,1])part('Nostril',darkSkin,[side*.037,.045,.331],[.019,.009,.009],head);
  part('Hair cap',hair,[0,.345,-.02],[.255,.115,.238],head);
  for(let j=0;j<13;j++) {
    const x=(j%5-2)*.09,z=-.11+Math.floor(j/5)*.10;
    const lock=part('Swept hair',hair,[x,.405+(j%3)*.017,z],[.057,.145,.065],head,new T.ConeGeometry(1,1,5));
    lock.rotation.x=-.6;lock.rotation.z=-.22;
  }
  model.updateMatrixWorld(true);
  const bounds=new T.Box3().setFromObject(model),size=bounds.getSize(new T.Vector3());
  const fit=Math.min(.72/size.x,.95/size.y,.72/size.z);model.scale.setScalar(fit);
  model.position.y=-bounds.min.y*fit;
  const animate=(t,showcase=false)=>{
    const breath=Math.sin(t*2.0),smash=showcase?Math.pow(Math.max(0,Math.sin(t*2)),6):0;
    const motion=root.userData.locomotion,stride=Math.sin(motion?.phase||0)*(motion?.amount||0);
    torso.scale.y=1+breath*.008;
    arms.forEach(({arm,forearm,side})=>{arm.rotation.z=side*(.16+breath*.013+smash*.19);arm.rotation.x=-smash*.75-side*stride*.32;forearm.rotation.x=-.20-smash*.42;});
    legs.forEach(({leg,side})=>{leg.rotation.x=Math.sin(t*3.0+side)*.018+side*stride*.45;});
    head.rotation.y=Math.sin(t*.7)*.075;head.rotation.x=smash*.10;
  };
  root.userData={modelRoot:model,modelReady:true,customRig:true,combatClass:'hulk',personality:'fierce',personalityRig:true,
    animationCount:3,cosAnim:[t=>animate(t)],showcaseAnim:t=>animate(t,true),showcaseReset:()=>animate(0)};
  return root;
}
