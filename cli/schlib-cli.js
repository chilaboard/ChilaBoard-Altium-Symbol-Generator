#!/usr/bin/env node
// Usage: node cli/schlib-cli.js parts.csv|parts.xlsx [out.SchLib] [--spacing 10] [--lenLR 30] [--lenTB 10] [--activeLow hash|overbar] [--order ccw|topdown]
const fs=require('fs'),path=require('path');
const CFB=require('../vendor/cfb.js'); require('../src/schlib_core.js'); const C=globalThis.SchLibCore;
const a=process.argv.slice(2); if(!a.length){console.log('Usage: node cli/schlib-cli.js parts.csv|parts.xlsx [out.SchLib] [options]');process.exit(1)}
const pos=[],o={};
for(let i=0;i<a.length;i++){ if(a[i].startsWith('--')){ const k=a[i].slice(2),v=a[++i]; o[k]=v; } else pos.push(a[i]); }
const inp=pos[0], out=pos[1]||inp.replace(/\.[^.]+$/,'')+'.SchLib';
let text;
if(/\.xlsx?$/i.test(inp)){ const X=require('../vendor/xlsx.mini.min.js'); const wb=X.readFile(inp);
  text=wb.SheetNames.map(n=>X.utils.sheet_to_csv(wb.Sheets[n],{blankrows:true})).join('\n\n'); }
else text=fs.readFileSync(inp,'utf8');
const R=C.parseParts(C.parseCSV(text));
R.errors.forEach(e=>console.error('ERROR:',e));
if(R.errors.length||!R.parts.length){console.error('No file written.');process.exit(2)}
const opt={}; if(o.spacing)opt.spacing=+o.spacing; if(o.lenLR)opt.lenLR=+o.lenLR; if(o.lenTB)opt.lenTB=+o.lenTB; if(o.activeLow)opt.activeLow=o.activeLow; if(o.order)opt.rightOrder=o.order;
const lib=C.buildSchLib(CFB,R.parts,opt);
fs.writeFileSync(out,CFB.write(lib.cfb,{type:'buffer'}));
console.log(`${R.parts.length} component(s) -> ${out}`);
