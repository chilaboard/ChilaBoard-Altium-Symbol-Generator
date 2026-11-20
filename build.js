// Builds docs/index.html (single self-contained file for GitHub Pages) from web/template.html
const fs=require('fs'),p=require('path'),r=f=>fs.readFileSync(p.join(__dirname,f),'utf8');
let h=r('web/template.html');
for(const [k,f] of [['/*CFB*/','vendor/cfb.js'],['/*XLSX*/','vendor/xlsx.mini.min.js'],['/*CORE*/','src/schlib_core.js']]){
  const v=r(f); if(/<\/script/i.test(v)) throw new Error('</script in '+f);
  h=h.split(k).join(v);
}
let pr=fs.readFileSync(p.join(__dirname,'prompts/AI_PROMPT.md'),'utf8');
const m=pr.match(/````text\n([\s\S]*?)\n````/); if(!m) throw new Error('prompt block not found');
const promptText=m[1]; if(/<\/script/i.test(promptText)) throw new Error('</script in prompt');
const logo='data:image/png;base64,'+fs.readFileSync(p.join(__dirname,'assets/logo.png')).toString('base64');
h=h.split('{{LOGO}}').join(logo);
h=h.split('{{PROMPT}}').join(promptText);
fs.writeFileSync(p.join(__dirname,'docs/index.html'),h); console.log('docs/index.html',h.length,'bytes');
