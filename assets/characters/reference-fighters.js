// Original code-native models built for the supplied character references.
// Faces and costumes are part of each rig, never overlays on another fighter.
import { mergeGeometries } from '../vendor/BufferGeometryUtils.js';
export const REFERENCE_FIGHTERS = [
  ['batman','Batman',0x77828d,0xe3bd68,'fierce'],
  ['bowser','Bowser',0xeebc24,0xff642b,'fierce'],
  ['buzz','Buzz',0x9cce3c,0x9470d6,'playful'],
  ['donatello','Donatello',0x819c39,0x9664d5,'sly'],
  ['joker','Joker',0x8d43b9,0xe44072,'manic'],
  ['marshmallow','Marshmallow',0xe4ebf3,0x89daff,'playful'],
  ['minion','Minion',0xf4ca38,0x528ac7,'playful'],
].map(([id,name,color,accent,personality])=>({id,name,color,accent,personality,
  belly:color,trim:accent,model:`procedural:${id}`,portrait:`assets/portraits/${id}.webp`,expression:'Signature',altExpression:'Wave'}));

export function createReferenceFighter(T, def) {
  const root=new T.Group(), model=new T.Group();root.add(model);
  const mats=new Map(), limbs=[], motions=[];
  const mat=(color,roughness=.58,metalness=0)=>{
    const key=`${color}:${roughness}:${metalness}`;
    if(!mats.has(key))mats.set(key,new T.MeshStandardMaterial({color,roughness,metalness}));
    return mats.get(key);
  };
  const black=mat(0x111521),white=mat(0xf4f4e9),skin=mat(0xe6b48b),steel=mat(0xadb8c3,.3,.65);
  const sphere=new T.SphereGeometry(1,20,14),box=new T.BoxGeometry(1,1,1);
  function part(name,m,p,s,parent=model,geo=sphere){
    const o=new T.Mesh(geo,m);o.name=name;o.position.set(...p);o.scale.set(...s);
    o.castShadow=o.receiveShadow=true;parent.add(o);return o;
  }
  function joint(name,p,parent=model){const g=new T.Group();g.name=name;g.position.set(...p);parent.add(g);return g;}
  const cube=(name,m,p,s,parent=model)=>part(name,m,p,s,parent,box);
  const cone=(name,m,p,s,parent=model)=>part(name,m,p,s,parent,new T.ConeGeometry(1,1,12));
  function tube(name,points,r,m,parent=model){return part(name,m,[0,0,0],[1,1,1],parent,
    new T.TubeGeometry(new T.CatmullRomCurve3(points.map(p=>new T.Vector3(...p))),16,r,6,false));}
  function rod(name,a,b,r,m,parent=model){
    const from=new T.Vector3(...a),to=new T.Vector3(...b),v=to.clone().sub(from);
    const o=part(name,m,from.add(to).multiplyScalar(.5).toArray(),[1,1,1],parent,new T.CylinderGeometry(r,r,v.length(),12));
    o.quaternion.setFromUnitVectors(new T.Vector3(0,1,0),v.normalize());return o;
  }
  function panel(name,points,m,parent=model,depth=.025){
    const shape=new T.Shape();points.forEach(([x,y],i)=>i?shape.lineTo(x,y):shape.moveTo(x,y));shape.closePath();
    return part(name,m,[0,0,0],[1,1,1],parent,new T.ExtrudeGeometry(shape,{depth,bevelEnabled:true,bevelSize:.006,bevelThickness:.006,bevelSegments:1,steps:1}));
  }
  function ring(name,p,r,thickness,m,parent=model){return part(name,m,p,[1,1,1],parent,new T.TorusGeometry(r,thickness,8,32));}
  function torso(m,p=[0,1.15,0],scale=[.38,.48,.24]){
    const points=[[0,-1],[.65,-1],[.8,-.7],[1,.3],[.88,.72],[.48,1],[0,1]].map(([r,y])=>new T.Vector2(r,y));
    return part('Tailored torso',m,p,scale,model,new T.LatheGeometry(points,28));
  }
  function arm(side,m,glove=m,{x=.43,y=1.48,length=.53,width=.105}={}){
    const a=joint('Arm'+side,[side*x,y,0]);a.rotation.z=side*.16;
    part('Upper arm',m,[0,-length*.24,0],[width,length*.32,width],a);
    part('Elbow',m,[0,-length*.5,0],[width*.91,width*.92,width*.92],a);
    part('Forearm',m,[0,-length*.72,.015],[width*.9,length*.3,width*.9],a);
    const hand=joint('Hand'+side,[0,-length-.06,.04],a);
    part('Palm',glove,[0,0,0],[width*1.16,width*1.2,width],hand);
    for(let f=0;f<3;f++)part('Finger',glove,[(f-1)*width*.65,-width*.75,.045],[width*.37,width*.6,width*.53],hand);
    part('Thumb',glove,[-side*width*.95,0,.06],[width*.48,width*.76,width*.51],hand);
    limbs.push({joint:a,side,kind:'arm',rest:a.rotation.z});return {a,hand};
  }
  function leg(side,m,boot=m,{x=.19,y=.8,length=.66,width=.13}={}){
    const l=joint('Leg'+side,[side*x,y,0]);
    part('Thigh',m,[0,-length*.24,0],[width,length*.34,width],l);
    part('Shin',m,[0,-length*.69,.005],[width*.86,length*.29,width*.86],l);
    part('Boot',boot,[0,-length,.08],[width*1.12,.105,width*1.65],l);
    limbs.push({joint:l,side,kind:'leg',rest:0});return l;
  }
  function eyes(h,{y=.08,z=.245,gap=.11,iris=0x448aa3,size=.065}={}){
    for(const side of [-1,1]){
      part('Eye socket',black,[side*gap,y,z],[size*1.16,size*.9,.025],h);
      part('Eye white',white,[side*gap,y,z+.016],[size,size*.72,.023],h);
      part('Iris',mat(iris,.34),[side*gap,y,z+.036],[size*.46,size*.56,.012],h);
      part('Pupil',black,[side*gap,y,z+.047],[size*.23,size*.4,.007],h);
      part('Eye glint',white,[side*gap-.009,y+.014,z+.053],[.008,.009,.004],h);
    }
  }
  function grin(h,{y=-.1,z=.266,width=.16}={}){
    part('Smile cavity',black,[0,y,z],[width,.055,.035],h);
    for(let i=0;i<7;i++)cube('Tooth',white,[(i-3)*width*.245,y+.006,z+.028],[width*.22,.041,.017],h);
  }
  let head;
  function batman(){
    const grey=mat(0x707e89,.64),capeMat=mat(0x151d27,.84),gold=mat(0xb4a05c,.43,.25);
    torso(grey,[0,1.21,0],[.43,.47,.25]);part('Trunks',black,[0,.82,0],[.30,.22,.23]);
    for(const side of [-1,1]){leg(side,grey,black);const {a}=arm(side,grey,black);
      part('Gauntlet',black,[0,-.4,0],[.12,.19,.115],a);
      for(let j=0;j<3;j++){const fin=cone('Gauntlet fin',black,[side*.14,-.27-j*.095,-.015],[.045,.16,.05],a);fin.rotation.z=-side*.6;}}
    head=joint('Head',[0,1.91,0]);
    part('Cowl',black,[0,.02,0],[.245,.31,.235],head);
    cube('Squared exposed jaw',skin,[0,-.115,.16],[.31,.25,.20],head);
    for(const side of [-1,1]){
      cone('Cowl ear',black,[side*.17,.36,-.015],[.074,.38,.07],head);
      const eye=panel('White cowl eye',[[0,0],[side*.12,.018],[side*.085,-.045]],white,head,.008);eye.position.set(side*.046,.075,.234);
    }
    tube('Mouth',[[-.075,-.15,.268],[0,-.157,.278],[.075,-.151,.268]],.008,black,head);
    const bat=panel('Bat chest emblem',[[-.27,0],[-.17,.09],[-.095,.03],[-.055,.12],[-.026,.075],[0,.11],[.026,.075],[.055,.12],[.095,.03],[.17,.09],[.27,0],[.16,.017],[.1,-.055],[.045,-.035],[0,-.115],[-.045,-.035],[-.1,-.055],[-.16,.017]],black);bat.position.set(0,1.39,.256);
    cube('Utility belt',gold,[0,.9,.04],[.62,.12,.44]);
    for(let i=-2;i<=2;i++){cube('Belt pouch',gold,[i*.115,.9,.28],[.093,.14,.055]);part('Pouch stud',black,[i*.115,.93,.31],[.012,.012,.006]);}
    const cape=panel('Scalloped cape',[[-.46,1.68],[.46,1.68],[.61,.21],[.42,.38],[.26,.14],[.11,.33],[0,.13],[-.12,.32],[-.29,.15],[-.43,.36],[-.6,.2]],capeMat);cape.position.z=-.28;
    motions.push((t,s)=>{cape.rotation.y=Math.sin(t*1.6)*(.035+s*.04);});
  }
  function bowser(){
    const gold=mat(0xe6af24,.54),cream=mat(0xe9cd89),green=mat(0x397940,.7),red=mat(0xc93c22,.5);
    part('Heavy body',gold,[0,.93,0],[.53,.63,.39]);
    for(let i=0;i<5;i++)part('Belly plate',cream,[0,.61+i*.16,.345],[.36-Math.abs(i-2)*.028,.13,.10]);
    const shell=part('Domed shell',green,[0,1.15,-.3],[.60,.63,.35]);
    const rim=ring('Ivory shell rim',[0,1.15,-.24],.56,.065,cream);rim.scale.y=1.08;
    for(let row=0;row<3;row++)for(let col=-1;col<=1;col++){
      const x=col*.29,y=.84+row*.28;
      const spike=cone('Shell spike',cream,[x,y,-.59],[.105,.30,.105]);spike.rotation.x=-Math.PI/2;
      ring('Spike base',[x,y,-.54],.11,.018,mat(0x986433));
    }
    for(const side of [-1,1]){
      leg(side,gold,gold,{x:.31,y:.55,length:.36,width:.21});
      const {a}=arm(side,gold,gold,{x:.49,y:1.33,length:.60,width:.20});
      for(const y of [-.15,-.48]){part('Black spiked cuff',black,[0,y,0],[.235,.105,.235],a);
        for(let j=0;j<5;j++){const angle=j*Math.PI*2/5;const spike=cone('Cuff spike',steel,[Math.sin(angle)*.235,y,Math.cos(angle)*.235],[.048,.115,.048],a);spike.quaternion.setFromUnitVectors(new T.Vector3(0,1,0),new T.Vector3(Math.sin(angle),0,Math.cos(angle)));}}
      for(let toe=0;toe<3;toe++){const claw=cone('Foot claw',cream,[side*.31+(toe-1)*.12,.09,.37],[.063,.18,.06]);claw.rotation.x=Math.PI/2;}
    }
    head=joint('Head',[0,1.64,.07]);part('Green cranium',green,[0,.08,0],[.39,.38,.32],head);
    part('Open roaring mouth',mat(0x421322),[0,-.15,.30],[.32,.21,.16],head);
    part('Lower jaw',cream,[0,-.28,.30],[.34,.10,.24],head);
    part('Broad muzzle',cream,[0,.014,.34],[.39,.19,.25],head);
    for(const side of [-1,1]){
      part('Nostril',mat(0x6c451c),[side*.14,.084,.562],[.037,.025,.014],head);
      part('Eye white',white,[side*.205,.23,.26],[.11,.13,.045],head);
      part('Red iris',red,[side*.19,.215,.304],[.044,.067,.017],head);
      part('Pupil',black,[side*.185,.217,.318],[.017,.048,.01],head);
      const brow=part('Flame eyebrow',red,[side*.20,.335,.265],[.16,.065,.065],head);brow.rotation.z=side*.3;
      const horn=cone('Ivory horn',cream,[side*.40,.31,-.04],[.11,.37,.10],head);horn.rotation.z=-side*.34;
      for(let j=0;j<3;j++){const tooth=cone('Fang',white,[side*(.07+j*.08),-.12,.46],[.039,.15,.037],head);tooth.rotation.z=Math.PI;}
    }
    for(let j=0;j<5;j++){const hair=cone('Flame mane',red,[0,.43-j*.055,-.12-j*.10],[.17,.32,.16],head);hair.rotation.x=-.5;}
    const tail=cone('Tail',gold,[0,.43,-.56],[.17,.56,.17]);tail.rotation.x=-1.05;
    motions.push((t,s)=>{shell.rotation.y=Math.sin(t)*.018;head.rotation.x=-s*.08;});
  }
  function buzz(){
    const suit=mat(0xeff2f0,.32),lime=mat(0x92c52c,.33),purple=mat(0x6544a0,.44);
    torso(suit,[0,1.12,0],[.41,.44,.29]);part('Ribbed waist',black,[0,.82,0],[.30,.14,.23]);
    for(let i=0;i<4;i++){const r=ring('Waist rib',[0,.77+i*.035,0],.27,.012,mat(0x42464b));r.rotation.x=Math.PI/2;r.scale.y=.8;}
    for(const side of [-1,1]){
      leg(side,suit,lime,{x:.21,y:.77,length:.62,width:.145});const {a}=arm(side,suit,suit,{x:.46,y:1.4,length:.55,width:.135});
      part('Shoulder armour',suit,[0,-.055,0],[.20,.16,.19],a);part('Wrist cuff',purple,[0,-.48,0],[.148,.065,.14],a);
      cube('Wrist computer',lime,[0,-.4,.115],[.15,.16,.07],a);
      const knee=part('Knee pad',suit,[side*.21,.4,.135],[.115,.12,.045]);
    }
    part('Chest armour',lime,[0,1.36,.23],[.39,.20,.12]);
    for(let j=0;j<3;j++)part('Chest button',mat([0x2e9fc8,0x289975,0xe93a41][j],.3),[-.25+j*.062,1.36,.348],[.025,.052,.018]);
    part('Red chest switch',mat(0xe33235,.28),[.23,1.38,.353],[.057,.057,.022]);
    cube('Ranger badge',white,[0,1.43,.345],[.15,.075,.025]);cube('Badge wings',steel,[0,1.43,.362],[.20,.018,.01]);
    const collar=ring('Pressure collar',[0,1.58,0],.32,.055,steel);collar.rotation.x=Math.PI/2;
    head=joint('Head',[0,1.87,0]);part('Purple hood',purple,[0,.035,0],[.255,.32,.24],head);
    part('Face',skin,[0,.01,.12],[.205,.255,.17],head);part('Square chin',skin,[0,-.18,.17],[.17,.09,.12],head);
    eyes(head,{y:.11,z:.255,gap:.09,size:.06});part('Nose',skin,[0,.02,.30],[.049,.066,.046],head);
    for(const side of [-1,1]){const brow=part('Eyebrow',mat(0x513723),[side*.09,.192,.256],[.085,.018,.021],head);brow.rotation.z=side*.16;}
    tube('Confident smile',[[-.09,-.10,.276],[0,-.125,.293],[.09,-.09,.276]],.008,mat(0x965644),head);
    const visorMat=new T.MeshStandardMaterial({color:0xbadceb,roughness:.12,metalness:.05,transparent:true,opacity:.11,depthWrite:false});
    part('Clear helmet dome',visorMat,[0,1.89,0],[.37,.41,.35]);
    cube('Jetpack',purple,[0,1.19,-.33],[.45,.61,.25]);
    for(const side of [-1,1]){const wing=cube('Wing',purple,[side*.55,1.38,-.35],[.57,.18,.075]);
      cube('Wing white panel',suit,[side*.55,1.41,-.30],[.53,.11,.027]);
      for(let i=0;i<3;i++){const stripe=cube('Wing red stripe',mat(0xcf3235),[side*(.34+i*.16),1.43,-.28],[.057,.07,.018]);stripe.rotation.z=-.24;}
      cube('Wing tip',lime,[side*.87,1.38,-.33],[.055,.28,.12]);}
  }
  function donatello(){
    const green=mat(0x829d35,.59),purple=mat(0x633991,.68),ochre=mat(0xd6a840),shellMat=mat(0x70462c,.83);
    torso(green,[0,1.08,0],[.35,.43,.245]);part('Turtle shell',shellMat,[0,1.13,-.25],[.43,.51,.22]);
    const rim=ring('Shell rim',[0,1.13,-.27],.42,.035,mat(0xa07847));rim.scale.y=1.2;
    for(let row=0;row<3;row++)for(const side of [-1,1]){
      const plate=panel('Plastron plate',[[-.132,-.075],[.11,-.075],[.132,-.05],[.132,.064],[.105,.082],[-.112,.082],[-.132,.058]],ochre,model,.065);
      plate.position.set(side*.145,.88+row*.18,.226);
    }
    cube('Belt',black,[0,.83,.03],[.65,.11,.49]);cube('Belt buckle',steel,[0,.83,.292],[.10,.10,.024]);
    for(const side of [-1,1]){
      const l=leg(side,green,green,{x:.2,y:.76,length:.61,width:.14});part('Knee wrap',purple,[0,-.3,.02],[.15,.12,.14],l);
      const {a,hand}=arm(side,green,green,{x:.37,y:1.4,length:.55,width:.13});
      part('Elbow wrap',purple,[0,-.3,0],[.137,.07,.137],a);part('Wrist wrap',purple,[0,-.51,.02],[.12,.075,.12],a);
      if(side===1){const staff=rod('Bo staff',[-.09,-.5,0],[.18,.86,0],.028,mat(0x976139,.81),hand);
        for(let i=0;i<7;i++)ring('Staff grip',[.017,.08+i*.03,0],.031,.006,mat(0x4e3022),hand).rotation.x=Math.PI/2;}
    }
    head=joint('Head',[0,1.78,0]);part('Turtle head',green,[0,.055,.04],[.31,.265,.26],head);
    part('Muzzle',green,[0,-.08,.18],[.28,.14,.18],head);
    part('Purple bandana',purple,[0,.12,.05],[.315,.092,.265],head);
    eyes(head,{y:.11,z:.302,gap:.135,size:.075,iris:0x5e3924});
    for(const side of [-1,1]){
      tube('Rectangular glasses',[[-.096,.075,0],[.096,.075,0],[.105,-.055,0],[.072,-.083,0],[-.085,-.083,0],[-.096,.075,0]],.016,black,head).position.set(side*.135,.115,.348);
      const brow=panel('Bandana brow',[[0,.01],[side*.135,.028],[side*.123,-.01],[0,-.025]],purple,head,.009);brow.position.set(side*.05,.165,.349);
    }
    cube('Glasses bridge',black,[0,.13,.35],[.072,.023,.024],head);grin(head,{y:-.096,z:.335,width:.19});
    for(const side of [-1,1]){const ribbon=panel('Bandana tail',[[0,0],[-.32,-.15],[-.39,-.42],[-.23,-.32],[.04,-.05]],purple,head);ribbon.position.set(-.24,.13,-.13+side*.035);ribbon.rotation.y=.3;}
    part('Chin',green,[0,-.2,.19],[.19,.06,.13],head);
  }
  function joker(){
    const purple=mat(0x663091,.7),green=mat(0x377138,.74),red=mat(0xb41d38,.38),face=mat(0xe3e2dc,.7);
    torso(purple,[0,1.17,0],[.34,.47,.23]);
    const vest=panel('Green waistcoat',[[-.20,1.53],[.20,1.53],[.19,.90],[0,.83],[-.19,.90]],green);vest.position.z=.231;
    for(const side of [-1,1]){
      leg(side,purple,black,{width:.10});arm(side,purple,white,{x:.35,length:.61,width:.09});
      const lapel=panel('Coat lapel',[[side*.27,1.6],[side*.07,1.44],[side*.18,1.20],[side*.29,1.36]],purple);lapel.position.z=.259;
      const collar=panel('Shirt collar',[[side*.14,1.59],[0,1.57],[side*.10,1.4]],white);collar.position.z=.27;
    }
    const tie=panel('Crimson tie',[[-.045,1.48],[.04,1.48],[.067,1.24],[0,1.16],[-.068,1.25]],red);tie.position.z=.28;
    for(let i=0;i<3;i++)part('Waistcoat button',mat(0xd6ad64),[.04,1.12-i*.09,.266],[.012,.012,.008]);
    head=joint('Head',[0,1.89,0]);part('Pale skull',face,[0,.015,0],[.23,.32,.21],head);
    part('Pointed chin',face,[0,-.23,.105],[.13,.12,.14],head);
    for(const side of [-1,1]){
      part('Dark eye makeup',black,[side*.10,.095,.199],[.096,.068,.022],head);
      part('Amber eye',mat(0xf0a329,.3),[side*.10,.09,.223],[.039,.023,.014],head);
      part('Pupil',black,[side*.1,.09,.235],[.013,.019,.006],head);
      const brow=part('Scowling brow',black,[side*.10,.157,.194],[.108,.020,.022],head);brow.rotation.z=side*.30;
      part('Sharp cheek',face,[side*.16,-.057,.139],[.075,.11,.09],head);
      tube('Red extended grin',[[side*.03,-.17,.224],[side*.13,-.11,.242],[side*.20,-.035,.195]],.019,red,head);
      for(let j=0;j<4;j++){const lock=part('Green hair curl',green,[side*(.20+j*.012),.14-j*.095,-.06],[.061,.13,.10],head);lock.rotation.z=side*.4;}
    }
    part('Long nose',face,[0,.008,.236],[.04,.092,.072],head);grin(head,{y:-.135,z:.224,width:.155});
    const hat=joint('Purple top hat',[0,.29,0],head);hat.rotation.z=.12;
    part('Hat crown',purple,[0,.16,0],[1,1,1],hat,new T.CylinderGeometry(.265,.275,.34,32));
    part('Hat brim',purple,[0,-.014,0],[.39,.028,.34],hat);
    part('Green hat band',green,[0,.025,0],[1,1,1],hat,new T.CylinderGeometry(.279,.279,.075,32));
    part('Lapel flower',red,[-.25,1.34,.25],[.047,.047,.028]);
    const card=cube('Playing card',white,[.275,1.02,.15],[.12,.19,.013]);card.rotation.z=-.2;
    const heart=panel('Card heart',[[0,-.027],[-.028,.002],[-.024,.021],[0,.015],[.024,.021],[.028,.002]],red);heart.position.set(.275,1.035,.16);heart.rotation.z=-.2;
  }
  function marshmallow(){
    const cloth=mat(0xe0e5e8,.9),seam=mat(0xb4c0c9,.82),helmet=mat(0xf8f8f2,.4);
    torso(cloth,[0,1.12,0],[.34,.43,.24]);
    for(const side of [-1,1]){const l=leg(side,cloth,white,{width:.12});const {a}=arm(side,cloth,white,{x:.37,length:.6,width:.11});
      for(let j=0;j<4;j++){part('Sleeve rib',seam,[0,-.34-j*.029,.095],[.08,.009,.018],a);part('Knee rib',seam,[0,-.30-j*.026,.11],[.095,.008,.015],l);}}
    const strap=cube('Diagonal utility strap',black,[0,1.19,.22],[.15,.84,.06]);strap.rotation.z=-.60;
    for(let i=0;i<2;i++){const pouch=cube('Utility pouch',mat(0x343c46),[-.04+i*.15,1.25+i*.14,.28],[.12,.19,.06]);pouch.rotation.z=-.6;}
    for(let i=-4;i<=4;i++)cube('Ribbed hem',seam,[i*.062,.79,.213],[.017,.067,.023]);
    head=joint('Head',[0,1.86,0]);
    part('Marshmallow helmet',helmet,[0,.05,0],[1,1,1],head,new T.CylinderGeometry(.285,.29,.54,40,1));
    for(const side of [-1,1])for(const diagonal of [-1,1]){
      const eye=part('Cross eye',black,[side*.12,.12,.268],[.025,.09,.018],head);eye.rotation.z=diagonal*.64;
    }
    tube('Helmet smile',[[-.19,-.075,.223],[-.10,-.16,.281],[0,-.18,.297],[.10,-.16,.281],[.19,-.075,.223]],.022,black,head);
    const rim=ring('Helmet lower rim',[0,-.224,0],.279,.013,seam,head);rim.rotation.x=Math.PI/2;
    motions.push((t,s)=>{head.rotation.z=Math.sin(t*1.9)*(.04+s*.09);});
  }
  function minion(){
    const yellow=mat(0xedc333,.47),denim=mat(0x3e7199,.88),stitch=mat(0x8facb9,.88);
    part('Capsule body',yellow,[0,.97,0],[1,1,1],model,new T.CapsuleGeometry(.38,.46,10,28));
    part('Denim trousers',denim,[0,0,0],[1,1,1],model,new T.LatheGeometry(
      [[0,.34],[.15,.37],[.27,.45],[.35,.56],[.391,.69],[.391,.80]].map(([r,y])=>new T.Vector2(r,y)),40));
    part('Curved overall bib',denim,[0,.83,0],[1,1,1],model,new T.CylinderGeometry(.39,.39,.35,24,1,true,-.66,1.32));
    for(const side of [-1,1]){
      part('Curved denim strap',denim,[0,1.0,0],[1,1,1],model,new T.CylinderGeometry(.393,.393,.33,8,1,true,side>0?.53:-.73,.20));
      part('Metal bib button',steel,[side*.19,.96,.36],[.025,.025,.012]);
      leg(side,denim,black,{x:.18,y:.37,length:.20,width:.11});arm(side,yellow,black,{x:.37,y:.86,length:.31,width:.065});
    }
    const pocket=panel('Bib pocket',[[-.105,.88],[.105,.88],[.1,.77],[0,.74],[-.10,.77]],denim);pocket.position.z=.388;
    tube('Pocket stitching',[[-.095,.88,.42],[-.09,.785,.42],[0,.754,.42],[.09,.785,.42],[.095,.88,.42]],.004,stitch);
    head=joint('Head',[0,1.30,0]);
    // The head rig carries the complete upper shell so goggles never float.
    part('Yellow head',yellow,[0,0,0],[.379,.35,.35],head);
    const band=ring('Goggle strap',[0,.015,0],.352,.03,black,head);band.rotation.x=Math.PI/2;
    for(const side of [-1,1]){
      part('Eye white',white,[side*.16,.045,.303],[.143,.15,.065],head);
      ring('Steel goggle',[side*.16,.045,.357],.148,.029,steel,head);
      part('Brown iris',mat(0x70512f,.3),[side*.14,.035,.369],[.058,.067,.024],head);
      part('Pupil',black,[side*.14,.034,.39],[.026,.042,.009],head);
      part('Eye highlight',white,[side*.14-.014,.06,.4],[.012,.016,.004],head);
      part('Goggle bolt',steel,[side*.322,.045,.28],[.047,.054,.042],head);
    }
    tube('Small smile',[[-.09,-.19,.377],[0,-.22,.392],[.11,-.16,.376]],.018,black,head);
    for(let i=0;i<3;i++)cube('Smile tooth',white,[-.035+i*.039,-.192,.397],[.035,.029,.009],head);
    for(let i=-2;i<=2;i++)tube('Fine hair',[[i*.034,.31,0],[i*.08,.37,-.005],[i*.12,.31,-.01]],.006,black,head);
  }
  ({batman,bowser,buzz,donatello,joker,marshmallow,minion}[def.id])();
  // Batch static costume details within each articulated joint. The limbs,
  // head, moving cape and shell remain independently animated.
  const parents=[];model.traverse(o=>{if(o.isGroup)parents.push(o);});
  for(const parent of parents){
    const batches=new Map();
    for(const child of parent.children){
      if(!child.isMesh || child.material.transparent || /Scalloped cape|Domed shell/.test(child.name))continue;
      if(!batches.has(child.material))batches.set(child.material,[]);
      batches.get(child.material).push(child);
    }
    for(const [material,children] of batches){
      if(children.length<2)continue;
      const geometries=children.map(child=>{
        child.updateMatrix();const geo=child.geometry.index?child.geometry.toNonIndexed():child.geometry.clone();
        return geo.applyMatrix4(child.matrix);
      });
      const geometry=mergeGeometries(geometries);
      geometries.forEach(geo=>geo.dispose());
      if(!geometry)throw new Error(`Could not batch ${def.id} costume`);
      const mesh=new T.Mesh(geometry,material);mesh.name='Batched costume details';mesh.castShadow=mesh.receiveShadow=true;
      children.forEach(child=>parent.remove(child));parent.add(mesh);
    }
  }
  model.updateMatrixWorld(true);const bounds=new T.Box3().setFromObject(model),size=bounds.getSize(new T.Vector3());
  const fit=Math.min(.72/size.x,(def.id==='minion'?.78:.95)/size.y,.72/size.z);model.scale.setScalar(fit);
  model.position.set(-(bounds.min.x+bounds.max.x)*fit/2,-bounds.min.y*fit,-(bounds.min.z+bounds.max.z)*fit/2);
  let showcase=false;
  function animate(t){
    const s=showcase?Math.max(0,Math.sin(t*1.8)):0;
    model.position.y=-bounds.min.y*fit+Math.sin(t*2)*.004;
    for(const limb of limbs){
      limb.joint.rotation.x=limb.kind==='arm'?Math.sin(t*1.8+limb.side)*.035-s*.24:Math.sin(t*1.8+limb.side)*.018;
      limb.joint.rotation.z=limb.rest+(limb.kind==='arm'?limb.side*s*.13:0);
    }
    head.rotation.y=Math.sin(t*.8)*.07;
    motions.forEach(fn=>fn(t,s));
  }
  root.userData={modelRoot:model,modelReady:true,customRig:true,combatClass:def.id,personality:def.personality,
    personalityRig:true,animationCount:3,cosAnim:[animate],showcaseAnim:t=>{showcase=true;animate(t);},
    showcaseReset:()=>{showcase=false;animate(0);}};
  return root;
}
