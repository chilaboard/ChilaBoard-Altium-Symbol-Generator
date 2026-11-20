/* SchLib core: CSV/rows -> Altium .SchLib (CFB). Format reverse-engineered from an Altium 24 sample. */
(function(root){
'use strict';
const enc = new TextEncoder();

/* ---------- CSV ---------- */
function parseCSV(text){
  if(text.charCodeAt(0)===0xFEFF) text=text.slice(1);
  const rows=[]; let row=[], cell='', q=false;
  for(let i=0;i<text.length;i++){
    const c=text[i];
    if(q){ if(c==='"'){ if(text[i+1]==='"'){cell+='"';i++;} else q=false; } else cell+=c; }
    else if(c==='"') q=true;
    else if(c===','||c==='\t'&&false){ row.push(cell); cell=''; }
    else if(c==='\n'||c==='\r'){ if(c==='\r'&&text[i+1]==='\n') i++; row.push(cell); rows.push(row); row=[]; cell=''; }
    else cell+=c;
  }
  if(cell!==''||row.length){ row.push(cell); rows.push(row); }
  return rows;
}

/* ---------- table rows -> parts ----------
 block = row starting with "Part Number" (header), next row = part info,
 then row starting with "Pin No." (header), then pin rows until blank row / next block */
const TYPE_MAP={input:0,in:0,i:0,io:1,bidir:1,bidirectional:1,inout:1,output:2,out:2,o:2,opencollector:3,oc:3,passive:4,p:4,hiz:5,highz:5,openemitter:6,oe:6,power:7,pwr:7,supply:7};
const SIDE_MAP={l:'L',left:'L',r:'R',right:'R',t:'T',top:'T',b:'B',bottom:'B'};
const norm=s=>String(s==null?'':s).trim();
function parseParts(rows){
  const parts=[], errors=[]; let i=0;
  while(i<rows.length){
    const r=rows[i].map(norm);
    if(r[0].toLowerCase()==='part number'){
      const hdr=r, info=(rows[i+1]||[]).map(norm);
      if(!info[0]){ errors.push(`Row ${i+2}: part info row is empty`); i++; continue; }
      const part={name:info[0],desc:'',params:[],footprint:'',fpdesc:'',pins:[],value:''};
      hdr.forEach((h,k)=>{
        const H=h.toUpperCase(), v=info[k]||'';
        if(!h) return;
        if(H==='PART NUMBER') return;
        if(H==='DESCRIPTION'){ part.desc=v; return; }
        if(H==='FOOTPRINT'){ part.footprint=v; return; }
        if(H==='FOOTPRINT DESCRIPTION'){ part.fpdesc=v; return; }
        if(H==='VERIFY') return;
        part.params.push([H,v]);
      });
      part.params.unshift(['MANF_P#',part.name]);
      const vp=part.params.find(p=>p[0]==='VALUE'); part.value=vp?vp[1]:'';
      i+=2;
      if(i<rows.length && norm(rows[i][0]).toLowerCase()==='pin no.'){
        const ph=rows[i].map(norm).map(s=>s.toLowerCase());
        const ci={no:ph.indexOf('pin no.'),name:ph.indexOf('pin name'),type:ph.indexOf('type'),side:ph.indexOf('side')};
        i++;
        for(;i<rows.length;i++){
          const q=rows[i].map(norm);
          if(q.every(x=>x==='')) break;
          if(q[0].toLowerCase()==='part number') break;
          const no=q[ci.no],nm=q[ci.name];
          if(no===''||nm===''){ errors.push(`${part.name}: row ${i+1} missing pin number or name`); continue; }
          const tk=(q[ci.type]||'passive').toLowerCase().replace(/[\s_-]/g,'');
          if(!(tk in TYPE_MAP)){ errors.push(`${part.name}: pin ${no}: unknown Type "${q[ci.type]}"`); continue; }
          const sk=(q[ci.side]||'left').toLowerCase();
          if(!(sk in SIDE_MAP)){ errors.push(`${part.name}: pin ${no}: unknown Side "${q[ci.side]}"`); continue; }
          part.pins.push({no,name:nm,type:TYPE_MAP[tk],side:SIDE_MAP[sk]});
        }
      } else errors.push(`${part.name}: no "Pin No." table after part row`);
      if(!part.pins.length) errors.push(`${part.name}: no pins`);
      const dup=new Set(), seen=new Set(); part.pins.forEach(p=>{ if(seen.has(p.no)) dup.add(p.no); seen.add(p.no); });
      if(dup.size) errors.push(`${part.name}: duplicate pin numbers: ${[...dup].join(', ')}`);
      if(/[\\/:*?"<>|]/.test(part.name)||part.name.length>31) errors.push(`${part.name}: library reference must be <=31 chars and without \\ / : * ? " < > |`);
      parts.push(part);
    } else i++;
  }
  return {parts,errors};
}

/* ---------- layout ---------- */
const DEF={spacing:10,lenLR:30,lenTB:10,charW:8,rightOrder:'ccw',activeLow:'hash'};
function displayName(n,mode){
  if(mode==='overbar') return n.split('/').map(s=>s.endsWith('#')?[...s.slice(0,-1)].map(c=>c+'\\').join(''):s).join('/');
  return n;
}
const plainLen=n=>n.replace(/\\/g,'').length;
function layout(part,opt){
  opt=Object.assign({},DEF,opt||{});
  const S={L:[],R:[],T:[],B:[]};
  part.pins.forEach(p=>S[p.side].push(Object.assign({},p)));
  // file order is counter-clockwise like the datasheet drawing: Left top->bottom, Bottom left->right,
  // Right bottom->top, Top right->left.  'ccw' keeps that geometry; 'topdown' lists every side top->bottom / left->right.
  if(opt.rightOrder==='ccw'){ S.R.reverse(); S.T.reverse(); }
  const sp=opt.spacing, cw=opt.charW;
  const ml=a=>a.reduce((m,p)=>Math.max(m,plainLen(displayName(p.name,opt.activeLow))),0);
  const nLR=Math.max(S.L.length,S.R.length), nTB=Math.max(S.T.length,S.B.length);
  const up=v=>Math.ceil(v/10)*10;
  const H=Math.max(up((nLR+1)*sp), up((ml(S.T)+ml(S.B))*cw+20), 20);
  const W=Math.max(up((nTB+1)*sp), up((ml(S.L)+ml(S.R))*cw+20), 40);
  const off=(arr,span)=>Math.max(0,Math.floor((span/sp-(arr.length+1))/2));
  const res=[];
  S.L.forEach((p,i)=>res.push(Object.assign(p,{x:0,y:-(i+1+off(S.L,H))*sp,rot:2,len:opt.lenLR})));
  S.R.forEach((p,i)=>res.push(Object.assign(p,{x:W,y:-(i+1+off(S.R,H))*sp,rot:0,len:opt.lenLR})));
  S.T.forEach((p,i)=>res.push(Object.assign(p,{x:(i+1+off(S.T,W))*sp,y:0,rot:1,len:opt.lenTB})));
  S.B.forEach((p,i)=>res.push(Object.assign(p,{x:(i+1+off(S.B,W))*sp,y:-H,rot:3,len:opt.lenTB})));
  return {W,H,pins:res,opt};
}

/* ---------- Altium records ---------- */
const rnd8=()=>Array.from({length:8},()=>String.fromCharCode(65+Math.floor(Math.random()*26))).join('');
const isAscii=s=>/^[\x00-\x7f]*$/.test(s);
const CP1252={0x20ac:0x80,0x201a:0x82,0x192:0x83,0x201e:0x84,0x2026:0x85,0x2020:0x86,0x2021:0x87,0x2c6:0x88,0x2030:0x89,0x160:0x8a,0x2039:0x8b,0x152:0x8c,0x17d:0x8e,0x2018:0x91,0x2019:0x92,0x201c:0x93,0x201d:0x94,0x2022:0x95,0x2013:0x96,0x2014:0x97,0x2dc:0x98,0x2122:0x99,0x161:0x9a,0x203a:0x9b,0x153:0x9c,0x17e:0x9e,0x178:0x9f};
function ansiBytes(s){ const o=[]; for(const ch of s){ const c=ch.codePointAt(0); o.push(c<0x100&&!(c>=0x80&&c<0xa0)?c:(CP1252[c]||0x3f)); } return Uint8Array.from(o); }
function cat(list){ const n=list.reduce((s,a)=>s+a.length,0), o=new Uint8Array(n); let p=0; list.forEach(a=>{o.set(a,p);p+=a.length;}); return o; }
const asc=s=>Uint8Array.from([...s].map(c=>c.charCodeAt(0)&255));
/* props: [key,value] pairs; empty / 0 values are omitted (as Altium does).
   Non-ASCII values are written as  %UTF8%Key=<utf8> ||| Key=<ansi>  exactly like the Altium 24 sample. */
function textRec(props){
  const segs=[];
  props.forEach(([k,v])=>{
    if(v===''||v==null||v===0) return; v=String(v);
    if(isAscii(v)) segs.push(asc(k+'='+v));
    else { segs.push(cat([asc('%UTF8%'+k+'='),enc.encode(v)]),new Uint8Array(0),new Uint8Array(0),cat([asc(k+'='),ansiBytes(v)])); }
  });
  const out=[asc('|')];
  segs.forEach((g,i)=>{ if(i) out.push(asc('|')); out.push(g); });
  out.push(Uint8Array.of(0));
  return block(cat(out),0);
}
function block(body,flag){ const o=new Uint8Array(4+body.length); o[0]=body.length&255; o[1]=(body.length>>8)&255; o[2]=(body.length>>16)&255; o[3]=flag; o.set(body,4); return o; }
function pstr(b){ if(b.length>255) b=b.slice(0,255); return cat([Uint8Array.of(b.length),b]); }
function pinRec(p,opt){
  const nm=enc.encode(displayName(p.name,opt.activeLow)), ds=enc.encode(p.no);
  const h=new Uint8Array(26), dv=new DataView(h.buffer);
  dv.setInt32(0,2,true); h[4]=0; dv.setInt16(5,1,true); h[7]=0;      // record 2, ?, OwnerPartId=1, display mode
  h[8]=0;h[9]=0;h[10]=0;h[11]=0;                                       // symbols: inner edge, outer edge, inside, outside
  h[12]=0;                                                             // description (empty pascal string)
  h[13]=1;                                                             // formal type
  h[14]=p.type;                                                        // electrical type
  h[15]=0x38|p.rot;                                                    // rotation + name/designator visible (+0x20 locked in sample: 0x38 = 0x20|0x10|0x08)
  dv.setInt16(16,p.len,true); dv.setInt16(18,p.x,true); dv.setInt16(20,p.y,true); dv.setInt32(22,0,true);
  const tail=cat([pstr(nm),pstr(ds),Uint8Array.of(0),pstr(asc('|&|')),Uint8Array.of(0)]);
  return block(cat([h,tail]),1);
}
function buildComponent(part,opt){
  const L=layout(part,opt), o=L.opt, recs=[]; let idx=0;
  const lib=part.name;
  const R=(props)=>{ recs.push(textRec(props)); };
  R([['RECORD',1],['LibReference',lib],['ComponentDescription',part.desc],['PartCount',2],['DisplayModeCount',1],['IndexInSheet',-1],['OwnerPartId',-1],['CurrentPartId',1],['LibraryPath','*'],['SourceLibraryName','*'],['TargetFileName','*'],['UniqueID',rnd8()],['AreaColor',11599871],['Color',128],['PartIDLocked','F'],['DesignItemId',lib],['AllPinCount',L.pins.length]]);
  part.params.forEach(([k,v],i)=>R([['RECORD',41],['IndexInSheet',i],['OwnerPartId',-1],['Location.X',-32],['Location.Y',32],['Color',8388608],['FontID',2],['IsHidden','T'],['Text',v],['Name',k],['UniqueID',rnd8()]]));
  let n=part.params.length;
  R([['RECORD',14],['IsNotAccesible','T'],['IndexInSheet',n++],['OwnerPartId',1],['Location.Y',-L.H],['Corner.X',L.W],['LineWidth',1],['Color',128],['AreaColor',11599871],['IsSolid','T'],['UniqueID',rnd8()]]);
  R([['RECORD',4],['IsNotAccesible','T'],['IndexInSheet',n++],['OwnerPartId',1],['Location.X',Math.round(L.W/2)],['Location.Y',-Math.round(L.H/2)],['Justification',4],['Color',8388608],['FontID',4],['Text','=VALUE'],['UniqueID',rnd8()]]);
  L.pins.forEach(p=>recs.push(pinRec(p,o)));
  R([['RECORD',34],['IndexInSheet',-1],['OwnerPartId',-1],['Location.Y',0],['Color',8388608],['FontID',2],['Text','U?'],['Name','Designator'],['ReadOnlyState',1],['UniqueID',rnd8()]]);
  R([['RECORD',41],['IndexInSheet',-1],['OwnerPartId',-1],['Location.Y',-L.H-10],['Color',8388608],['FontID',2],['IsHidden','T'],['Text','=VALUE'],['Name','Comment'],['UniqueID',rnd8()]]);
  if(part.footprint){
    const owner=recs.length;   // index of RECORD=44 below
    R([['RECORD',44]]);
    R([['RECORD',45],['OwnerIndex',owner],['IndexInSheet',-1],['Description',part.fpdesc],['ModelName',part.footprint],['ModelType','PCBLIB'],['DatafileCount',1],['ModelDatafileEntity0',part.footprint],['ModelDatafileKind0','PCBLib'],['IsCurrent','T'],['UniqueID',rnd8()]]);
    R([['RECORD',46],['OwnerIndex',owner+1]]);
    R([['RECORD',48],['OwnerIndex',owner+1]]);
  }
  return {data:cat(recs),count:recs.length,lib,desc:part.desc,layout:L};
}
function buildSchLib(CFB,parts,opt){
  const comps=parts.map(p=>buildComponent(p,opt));
  const total=comps.reduce((s,c)=>s+c.count,0);
  const hp=[['HEADER','Protel for Windows - Schematic Library Editor Binary File Version 5.0'],['Weight',total+1],['MinorVersion',9],['UniqueID',rnd8()],['FontIdCount',4],['Size1',10],['FontName1','Times New Roman'],['Size2',10],['FontName2','Arial'],['Size3',10],['Underline3','T'],['FontName3','Times New Roman'],['Size4',12],['Bold4','T'],['FontName4','Arial'],['UseMBCS','T'],['IsBOC','T'],['SheetStyle',9],['BorderOn','T'],['SheetNumberSpaceSize',12],['AreaColor',16317695],['SnapGridOn','T'],['SnapGridSize',10],['VisibleGridOn','T'],['VisibleGridSize',10],['CustomX',18000],['CustomY',18000],['UseCustomSheet','T'],['ReferenceZonesOn','T'],['Display_Unit','0'],['CompCount',comps.length]];
  comps.forEach((c,i)=>{ hp.push(['LibRef'+i,c.lib],['CompDescr'+i,c.desc],['PartCount'+i,2]); });
  const c=CFB.utils.cfb_new({root:'Root Entry',CLSID:'0ef895759b9db044adb0c5b4742526be'});
  CFB.utils.cfb_add(c,'/FileHeader',textRec(hp));
  comps.forEach(k=>CFB.utils.cfb_add(c,'/'+k.lib+'/Data',k.data));
  CFB.utils.cfb_add(c,'/Storage',textRec([['HEADER','Icon storage'],['Weight','0']]));
  { const ix=c.FullPaths.findIndex(p=>p.indexOf('Sh33tJ5')>=0); if(ix>=0){ c.FullPaths.splice(ix,1); c.FileIndex.splice(ix,1); } }
  CFB.utils.cfb_gc(c);
  comps.forEach(k=>{ const e=CFB.find(c,'/'+k.lib+'/'); if(e) e.clsid='78149d9fb0ce8045af611c393b5c481d'; });
  return {comps,cfb:c};
}
root.SchLibCore={parseCSV,parseParts,layout,buildComponent,buildSchLib,textRec,DEF,displayName,TYPE_MAP};
})(typeof window!=='undefined'?window:globalThis);
